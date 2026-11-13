// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "/VotingToken.sol";
//import "./IExecutableProposal.sol";

contract QuadraticVoting {

    
    // Estructuras
    struct Proposal {
        string title;
        string description;
        address proposer;
        uint256 budget;
        address executor;  // Contrato que implementa IExecutableProposal
        uint256 votes;
        uint256 tokens;
        bool isApproved;
        bool isCancelled;
        bool isSignaling; // true si es una propuesta de signaling (presupuesto = 0)
    }
    
    struct Vote {
        uint256 votes;
        uint256 tokens;
    }
    
    // Variables de estado
    address immutable owner;
    VotingToken public token;
    uint256 immutable precioPorToken; //precio de cada token
    uint256 immutable maxTokensEnVenta; //numero maximo de token a la venta para poder votar
    uint256 public presupuestoTotal; //presupuesto total para las propuestas
    uint256 public numProposals;
    bool public votingOpen; //variable que dice si esta abiera o no la votacion
    
    
    mapping(address => bool) public participants;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Vote)) public votes;
    mapping(address => uint256) public participantCount;
    
    
    // Eventos
    event VotingOpened(uint256 budget, address owner);
    event VotingClosed();
    event ProposalAdded(uint256 id, string title, uint256 budget);
    event ProposalCancelled(uint256 id);
    event ProposalApproved(uint256 id, uint256 budget);
    event TokensBought(address buyer, uint256 amount);
    event TokensSold(address seller, uint256 amount);
    event VotesStaked(address voter, uint256 proposalId, uint256 votes, uint256 tokens);
    event VotesWithdrawn(address voter, uint256 proposalId, uint256 votes, uint256 tokens);
    // Modificadores
    modifier onlyOwner() {
        require(msg.sender == owner, "Solo el propietario puede ejecutar esta funcion");
        _;
    }
    
    modifier onlyParticipant() {
        require(participants[msg.sender], "Solo los participantes pueden ejecutar esta funcion");
        _;
    }
    
    modifier votingIsOpen() {
        require(votingOpen, "El periodo de votacion no esta abierto");
        _;
    }

    constructor(uint _precioToken, uint _maxTokens) {
        require(_precioToken > 0 && _maxTokens > 0, "Los valores tienen que ser mayores que 0"); 
        owner = msg.sender; //guarda el dueño del contrato (habrá funciones que solo puede hacer el)
        precioPorToken = _precioToken; //inicializa el precio por cada token
        maxTokensEnVenta = _maxTokens; //inicializa el numero maximo de tokens que estan en venta para votar
        
        token = new VotingToken("Voting Token", "VOTE", _maxTokens, owner); // Crear el contrato de tokens
        votingOpen = false; //inicializa que todavia no se ha abierto la votacion
    }

    function openVoting() external payable onlyOwner { //solo lo puede ejecutar el dueño del contrato y es para comenzar la votacion con su presupuesto inicial
        require(!votingOpen, "La votacion ya esta abierta."); //comprueba que la votacion no ha sido iniciada
        require(msg.value > 0, "El presupuesto inicial debe ser mayor que 0."); //comprueba que el presupuesto inicial es mayor que 0

        votingOpen = true; //cambia la variable para que marque que ahora si esta abierta la votacion
        presupuestoTotal = msg.value; //inicializa el presupuesto total de la propuesta a la inical (puede aumentar y disminuir dependiendo de las propuestas)
        // Limpiar arrays de propuestas de la votación anterior (si existe)
        delete pendingProposalIds;
        delete approvedProposalIds;
        delete signalingProposalIds;
        
        emit VotingOpened(_presupuestoInicial, owner); //hace el evento indicando el presupuesto inicial de la propuesta y el dueño que es tambien el del contrato
    }
    function addParticipant() external payable {
        require(!participants[msg.sender], "Ya eres un participante");
        require(msg.value >= tokenPrice, "Debes comprar al menos un token");
        
        uint256 tokenAmount = msg.value / tokenPrice;
        
        
        require(token.totalSupply() + tokenAmount <= maxTokens, "No hay suficientes tokens disponibles");// Verificar que no exceda el máximo de tokens disponibles
        
      
        participants[msg.sender] = true;  // Registrar participante
        numParticipants++;
        
        
        token.mint(msg.sender, tokenAmount);// Crear tokens para el participante
        
        emit ParticipantAdded(msg.sender);
        emit TokensBought(msg.sender, tokenAmount);
    }
    
    function removeParticipant() external onlyParticipant {
        participants[msg.sender] = false;
        numParticipants--;
        
        emit ParticipantRemoved(msg.sender);
    }
    function addProposal(string calldata title, string calldata description, uint256 budget, address executor) external votingIsOpen onlyParticipant returns (uint256) {
        require(executor != address(0), "Direccion de ejecutor invalida");//comprobamos que la dirección del ejecutor no sea la dirección cero (address(0))
        
        uint256 proposalId = numProposals++;  // Se asigna un ID único a la propuesta incrementando el contador numProposals
        Proposal storage newProposal = proposals[proposalId]; //Se crea una nueva entrada en el mapping proposals con ese ID
    

        newProposal.title = title;
        newProposal.description = description;
        newProposal.proposer = msg.sender;
        newProposal.budget = budget;
        newProposal.executor = executor;
        newProposal.votes = 0;
        newProposal.tokens = 0;
        newProposal.isApproved = false;
        newProposal.isCancelled = false;
        newProposal.isSignaling = (budget == 0);
        
    
        if (newProposal.isSignaling) {// Si es una propuesta de signaling (presupuesto = 0), se añade a la lista signalingProposalIds
            signalingProposalIds.push(proposalId);
        } else {// Si es una propuesta de financiación (presupuesto > 0), se añade a la lista pendingProposalIds
            pendingProposalIds.push(proposalId);
        }
        
        emit ProposalAdded(proposalId, title, budget, newProposal.isSignaling);
        
        return proposalId;
    }
    function cancelProposal(uint256 proposalId) external votingIsActive {
        Proposal storage proposal = proposals[proposalId];
        
        require(proposal.proposer == msg.sender, "Solo el creador puede cancelar la propuesta");
      
        
        
        proposal.state = ProposalState.Cancelled;// Marcar como cancelada
        
        
        uint256 indexToRemove = proposal.proposalIndex; // Obtener el índice del elemento en la lista de propuesta
        uint256[] storage sourceArray;
        
        if (proposal.isSignaling) {
            sourceArray = signalingProposalIds;
        } else {
            sourceArray = pendingProposalIds;
        }
        
        
        if (sourceArray.length > 0 && indexToRemove < sourceArray.length) {//  si hay elementos en el array y el índice es válido
          
            uint256 lastProposalId = sourceArray[sourceArray.length - 1];  // Obtenemos el último elemento del array
            
            if (proposalId != lastProposalId) {
                
                sourceArray[indexToRemove] = lastProposalId;// Mover el último elemento al lugar del eliminado
                
                
                proposals[lastProposalId].proposalIndex = indexToRemove;// Actualizar el índice en el elemento movido
            }
            
           
            sourceArray.pop(); // Eliminar el último elemento
        }
        
        cancelledProposalIds.push(proposalId); // Añadir a la lista de canceladas
       
        
        emit ProposalCancelled(proposalId);
    }



}