// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VotingToken} from "./VotingToken.sol";
import {IExecutableProposal} from "./IExecutableProposal.sol";

/**
 * @title QuadraticVoting
 * @notice Sistema de gobernanza descentralizada con votación cuadrática on-chain
 */
contract QuadraticVoting {
   
    struct Proposal {
        string title;
        string description;
        address proposer;
        uint256 budget;
        address executor;
        uint256 votes;
        uint256 tokens;
        bool isApproved;
        bool isCancelled;
        bool isSignaling;
    }
    
    struct Vote {
        uint256 votes;
        uint256 tokens;
    }
    
    address public immutable owner;
    VotingToken public immutable token;
    uint256 public immutable precioPorToken;
    uint256 public immutable maxTokensEnVenta;
    
    uint256 public presupuestoTotal;
    uint256 public numProposals;
    uint256 public numParticipants;
    bool public votingOpen;
    
    mapping(address => bool) public participants;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Vote)) public votes;
    
    uint256[] public pendingProposalIds;
    uint256[] public approvedProposalIds;
    uint256[] public signalingProposalIds;
    uint256[] public cancelledProposalIds;

    event VotingOpened(uint256 budget, address owner);
    event VotingClosed();
    event ParticipantAdded(address participant);
    event ParticipantRemoved(address participant);
    event ProposalAdded(uint256 id, string title, uint256 budget, bool isSignaling);
    event ProposalCancelled(uint256 id);
    event ProposalApproved(uint256 id, uint256 budget);
    event TokensBought(address buyer, uint256 amount);
    event TokensSold(address seller, uint256 amount);
    event VotesStaked(address voter, uint256 proposalId, uint256 votes, uint256 tokens);
    event VotesWithdrawn(address voter, uint256 proposalId, uint256 votes, uint256 tokens);
    event RefundClaimed(address voter, uint256 proposalId, uint256 tokens);

    error NotOwner();
    error NotParticipant();
    error VotingNotOpen();
    error VotingAlreadyOpen();
    error InvalidValues();
    error InsufficientFunds();
    error MaxTokensExceeded();
    error AlreadyParticipant();
    error InvalidExecutor();
    error NotProposer();
    error InvalidProposal();
    error CannotRefund();
    error NoVotesToRefund();
    error TransferFailed();
    error ProposalNotApprovedOrSignaling();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
    
    modifier onlyParticipant() {
        if (!participants[msg.sender]) revert NotParticipant();
        _;
    }
    
    modifier votingIsOpen() {
        if (!votingOpen) revert VotingNotOpen();
        _;
    }

    /**
     * @notice Constructor del contrato
     * @param _precioToken Precio en wei de cada token
     * @param _maxTokens Número máximo de tokens que se pueden mintear
     */
    constructor(uint256 _precioToken, uint256 _maxTokens) {
        if (_precioToken == 0 || _maxTokens == 0) revert InvalidValues();
        
        owner = msg.sender;
        precioPorToken = _precioToken;
        maxTokensEnVenta = _maxTokens;
        
        // Se asume que VotingToken implementa mint y burn con control de accesos
        token = new VotingToken("Voting Token", "VOTE", _maxTokens, address(this));
    }

    /**
     * @notice Abre el proceso de votación y establece el presupuesto inicial
     */
    function openVoting() external payable onlyOwner {
        if (votingOpen) revert VotingAlreadyOpen();
        if (msg.value == 0) revert InvalidValues();

        votingOpen = true;
        presupuestoTotal = msg.value;
        
        delete pendingProposalIds;
        delete approvedProposalIds;
        delete signalingProposalIds;
        delete cancelledProposalIds;
        
        emit VotingOpened(msg.value, owner);
    }

    /**
     * @notice Permite a un usuario inscribirse y comprar tokens iniciales
     */
    function addParticipant() external payable {
        if (participants[msg.sender]) revert AlreadyParticipant();
        if (msg.value < precioPorToken) revert InsufficientFunds();
        
        uint256 tokenAmount = msg.value / precioPorToken;
        if (token.totalSupply() + tokenAmount > maxTokensEnVenta) revert MaxTokensExceeded();
        
        participants[msg.sender] = true;
        numParticipants++;
        
        token.mint(msg.sender, tokenAmount);
        
        emit ParticipantAdded(msg.sender);
        emit TokensBought(msg.sender, tokenAmount);
    }

    /**
     * @notice Elimina a un participante del sistema
     */
    function removeParticipant() external onlyParticipant {
        participants[msg.sender] = false;
        numParticipants--;
        emit ParticipantRemoved(msg.sender);
    }

    /**
     * @notice Crea una nueva propuesta de financiación o de signaling
     * @param title Título de la propuesta
     * @param description Descripción detallada
     * @param budget Presupuesto solicitado (0 para signaling)
     * @param executor Dirección del contrato que implementa IExecutableProposal
     * @return Identificador único de la propuesta
     */
    function addProposal(string calldata title, string calldata description, uint256 budget, address executor) external votingIsOpen onlyParticipant returns (uint256) {
        if (executor == address(0)) revert InvalidExecutor();
        
        uint256 proposalId = numProposals++;
        Proposal storage newProposal = proposals[proposalId];
        
        newProposal.title = title;
        newProposal.description = description;
        newProposal.proposer = msg.sender;
        newProposal.budget = budget;
        newProposal.executor = executor;
        newProposal.isSignaling = (budget == 0);
        
        if (newProposal.isSignaling) {
            signalingProposalIds.push(proposalId);
        } else {
            pendingProposalIds.push(proposalId);
        }
        
        emit ProposalAdded(proposalId, title, budget, newProposal.isSignaling);
        return proposalId;
    }

    /**
     * @notice Cancela una propuesta activa
     * @param proposalId Identificador de la propuesta
     */
    function cancelProposal(uint256 proposalId) external votingIsOpen {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.proposer != msg.sender) revert NotProposer();
        if (proposal.isApproved || proposal.isCancelled) revert InvalidProposal();
        
        proposal.isCancelled = true;
        
        if (proposal.isSignaling) {
            _removeFromArray(signalingProposalIds, proposalId);
        } else {
            _removeFromArray(pendingProposalIds, proposalId);
        }
        
        cancelledProposalIds.push(proposalId);
        emit ProposalCancelled(proposalId);
    }

    /**
     * @notice Compra tokens adicionales para votar
     */
    function buyTokens() external payable onlyParticipant votingIsOpen {
        if (msg.value < precioPorToken) revert InsufficientFunds();
        
        uint256 tokenAmount = msg.value / precioPorToken;
        if (token.totalSupply() + tokenAmount > maxTokensEnVenta) revert MaxTokensExceeded();
        
        token.mint(msg.sender, tokenAmount);
        emit TokensBought(msg.sender, tokenAmount);
    }

    /**
     * @notice Vende tokens no utilizados y recupera el Ether
     * @param amount Cantidad de tokens a vender
     */
    function sellTokens(uint256 amount) external onlyParticipant {
        // Requiere que el usuario haya hecho approve previo
        token.transferFrom(msg.sender, address(this), amount);
        token.burn(amount);
        
        uint256 ethToReturn = amount * precioPorToken;
        (bool success, ) = msg.sender.call{value: ethToReturn}("");
        if (!success) revert TransferFailed();
        
        emit TokensSold(msg.sender, amount);
    }

    /**
     * @notice Deposita votos en una propuesta usando coste cuadrático
     * @param proposalId Identificador de la propuesta
     * @param votesToAdd Cantidad de votos adicionales a depositar
     */
    function stake(uint256 proposalId, uint256 votesToAdd) external onlyParticipant votingIsOpen {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.isApproved || proposal.isCancelled) revert InvalidProposal();
        
        Vote storage userVote = votes[proposalId][msg.sender];
        
        uint256 currentVotes = userVote.votes;
        uint256 newTotalVotes = currentVotes + votesToAdd;
        
        uint256 currentCost = currentVotes * currentVotes;
        uint256 newTotalCost = newTotalVotes * newTotalVotes;
        uint256 tokensToPay = newTotalCost - currentCost;
        
        userVote.votes = newTotalVotes;
        userVote.tokens += tokensToPay;
        
        proposal.votes += votesToAdd;
        proposal.tokens += tokensToPay;
        
        // El usuario debe haber aprobado el gasto (approve) antes de llamar a esta función
        token.transferFrom(msg.sender, address(this), tokensToPay);
        
        emit VotesStaked(msg.sender, proposalId, votesToAdd, tokensToPay);
        
        if (!proposal.isSignaling) {
            _checkAndExecuteProposal(proposalId);
        }
    }

    /**
     * @notice Retira votos de una propuesta y devuelve el coste cuadrático proporcional
     * @param proposalId Identificador de la propuesta
     * @param votesToRemove Cantidad de votos a retirar
     */
    function withdrawFromProposal(uint256 proposalId, uint256 votesToRemove) external onlyParticipant votingIsOpen {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.isApproved || proposal.isCancelled) revert InvalidProposal();
        
        Vote storage userVote = votes[proposalId][msg.sender];
        if (userVote.votes < votesToRemove) revert InvalidValues();
        
        uint256 currentVotes = userVote.votes;
        uint256 newTotalVotes = currentVotes - votesToRemove;
        
        uint256 currentCost = currentVotes * currentVotes;
        uint256 newTotalCost = newTotalVotes * newTotalVotes;
        uint256 tokensToRefund = currentCost - newTotalCost;
        
        userVote.votes = newTotalVotes;
        userVote.tokens -= tokensToRefund;
        
        proposal.votes -= votesToRemove;
        proposal.tokens -= tokensToRefund;
        
        token.transfer(msg.sender, tokensToRefund);
        
        emit VotesWithdrawn(msg.sender, proposalId, votesToRemove, tokensToRefund);
    }

    /**
     * @notice Cierra el proceso de votación
     * @dev Utiliza el patrón Pull-over-Push para delegar los reembolsos en claimRefund
     */
    function closeVoting() external onlyOwner votingIsOpen {
        votingOpen = false;
        
        uint256 remainingBudget = presupuestoTotal;
        presupuestoTotal = 0; // Previene ataques de reentrancia
        
        if (remainingBudget > 0) {
            (bool success, ) = owner.call{value: remainingBudget}("");
            if (!success) revert TransferFailed();
        }
        
        emit VotingClosed();
    }

    /**
     * @notice Permite a los participantes reclamar sus tokens bloqueados (Patrón Pull-over-Push)
     * @param proposalId Identificador de la propuesta
     */
    function claimRefund(uint256 proposalId) external {
        Vote storage userVote = votes[proposalId][msg.sender];
        if (userVote.tokens == 0) revert NoVotesToRefund();

        Proposal storage prop = proposals[proposalId];
        
        // Se puede reembolsar si fue cancelada, o si la votación terminó y (era signaling o no fue aprobada)
        bool canRefund = prop.isCancelled || (!votingOpen && !prop.isApproved);
        if (!canRefund) revert CannotRefund();

        uint256 tokensToRefund = userVote.tokens;
        userVote.votes = 0;
        userVote.tokens = 0;

        token.transfer(msg.sender, tokensToRefund);
        emit RefundClaimed(msg.sender, proposalId, tokensToRefund);
    }

    /**
     * @notice Ejecuta una propuesta de signaling una vez cerrada la votación
     * @param proposalId Identificador de la propuesta
     */
    function executeSignalingProposal(uint256 proposalId) external {
        if (votingOpen) revert VotingAlreadyOpen();
        Proposal storage prop = proposals[proposalId];
        if (!prop.isSignaling || prop.isApproved || prop.isCancelled) revert ProposalNotApprovedOrSignaling();
        
        prop.isApproved = true;
        
        try IExecutableProposal(prop.executor).executeProposal{gas: 100000}(proposalId, prop.votes, prop.tokens) {} catch {}
    }

    /**
     * @notice Evalúa si una propuesta cumple el umbral y la ejecuta
     * @param proposalId Identificador de la propuesta
     */
    function _checkAndExecuteProposal(uint256 proposalId) internal {
        Proposal storage prop = proposals[proposalId];
        
        if (presupuestoTotal < prop.budget) return;

        // threshold = (0.2 + budget/totalbudget) * numParticipants + numPendingProposals
        // En enteros: ((20 * totalBudget + 100 * budget) * numParticipants) / (100 * totalBudget) + numPending
        uint256 threshold = ((20 * presupuestoTotal + 100 * prop.budget) * numParticipants) / (100 * presupuestoTotal) + pendingProposalIds.length;
        
        if (prop.votes > threshold) {
            prop.isApproved = true;
            presupuestoTotal -= prop.budget;
            
            // Los tokens gastados representan Ether aportado. Se queman y su valor aumenta el presupuesto total.
            presupuestoTotal += (prop.tokens * precioPorToken);
            token.burn(prop.tokens);

            _removeFromArray(pendingProposalIds, proposalId);
            approvedProposalIds.push(proposalId);

            // Limitamos a 100,000 gas para evitar ataques de DoS por parte del contrato externo
            try IExecutableProposal(prop.executor).executeProposal{value: prop.budget, gas: 100000}(proposalId, prop.votes, prop.tokens) {} catch {}
            
            emit ProposalApproved(proposalId, prop.budget);
        }
    }

    /**
     * @notice Función auxiliar para eliminar un elemento de un array dinámico optimizando gas
     * @param array Referencia al array
     * @param element Elemento a buscar y eliminar
     */
    function _removeFromArray(uint256[] storage array, uint256 element) internal {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; i++) {
            if (array[i] == element) {
                array[i] = array[length - 1]; // Intercambia con el último elemento
                array.pop(); // Elimina el último elemento
                break;
            }
        }
    }

    function getERC20() external view returns (address) {
        return address(token);
    }
    
    function getPendingProposals() external view votingIsOpen returns (uint256[] memory) {
        return pendingProposalIds;
    }
    
    function getApprovedProposals() external view votingIsOpen returns (uint256[] memory) {
        return approvedProposalIds;
    }
    
    function getSignalingProposals() external view votingIsOpen returns (uint256[] memory) {
        return signalingProposalIds;
    }
    
    function getProposalInfo(uint256 proposalId) external view votingIsOpen returns (Proposal memory) {
        return proposals[proposalId];
    }
}