// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {QuadraticVoting} from "../src/QuadraticVoting.sol";
import {VotingToken} from "../src/VotingToken.sol";
import {IExecutableProposal} from "../src/IExecutableProposal.sol";

/**
 * @title MockExecutor
 * @notice Contrato falso para simular la ejecución de una propuesta externa y recibir fondos
 */
contract MockExecutor is IExecutableProposal {
    bool public executed;
    uint256 public receivedAmount;
    
    event ExecutedWithData(uint256 proposalId, uint256 numVotes, uint256 numTokens);

    function executeProposal(uint256 proposalId, uint256 numVotes, uint256 numTokens) external payable override {
        executed = true;
        receivedAmount = msg.value;
        emit ExecutedWithData(proposalId, numVotes, numTokens);
    }
}

/**
 * @title QuadraticVotingTest
 * @notice Suite de tests para comprobar la votación cuadrática, umbrales y patrón Pull-over-Push
 */
contract QuadraticVotingTest is Test {
    QuadraticVoting public voting;
    VotingToken public token;
    MockExecutor public executor;
    
    address owner = address(this);
    address user1 = address(0x1);
    address user2 = address(0x2);

    uint256 constant TOKEN_PRICE = 0.01 ether; // 1 token = 0.01 ETH
    uint256 constant MAX_TOKENS = 10000;
    
    function setUp() public {
        // Desplegar el contrato principal
        voting = new QuadraticVoting(TOKEN_PRICE, MAX_TOKENS);
        token = VotingToken(voting.getERC20());
        executor = new MockExecutor();

        // Dar Ether a los usuarios de prueba
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    /**
     * @notice Testea la apertura de la votación y el registro de participantes
     */
    function testOpenVotingAndAddParticipant() public {
        voting.openVoting{value: 10 ether}();
        assertEq(voting.presupuestoTotal(), 10 ether);
        assertTrue(voting.votingOpen());

        vm.startPrank(user1);
        voting.addParticipant{value: 1 ether}();
        
        // 1 ether / 0.01 ether = 100 tokens
        assertEq(token.balanceOf(user1), 100);
        assertTrue(voting.participants(user1));
        vm.stopPrank();
    }

    /**
     * @notice Testea que el coste de los votos sea exactamente cuadrático
     */
    function testQuadraticStakingMath() public {
        voting.openVoting{value: 10 ether}();
        
        vm.startPrank(user1);
        voting.addParticipant{value: 1 ether}(); // Obtiene 100 tokens
        
        uint256 proposalId = voting.addProposal("Prop 1", "Desc", 5 ether, address(executor));
        
        // El usuario debe hacer approve antes de votar
        token.approve(address(voting), 100);

        // Stake 1 voto -> coste: 1^2 = 1 token
        voting.stake(proposalId, 1);
        (uint256 votes, uint256 tokensCost) = voting.votes(proposalId, user1);
        assertEq(votes, 1);
        assertEq(tokensCost, 1);
        assertEq(token.balanceOf(user1), 99); // 100 - 1

        // Stake 2 votos más (Total 3 votos) -> coste total: 3^2 = 9 tokens. Debería cobrar la diferencia (8)
        voting.stake(proposalId, 2);
        (votes, tokensCost) = voting.votes(proposalId, user1);
        assertEq(votes, 3);
        assertEq(tokensCost, 9);
        assertEq(token.balanceOf(user1), 91); // 99 - 8

        vm.stopPrank();
    }

    /**
     * @notice Testea el retiro de votos y la devolución matemática correcta
     */
    function testWithdrawVotesQuadraticRefund() public {
        voting.openVoting{value: 10 ether}();
        
        vm.startPrank(user1);
        voting.addParticipant{value: 1 ether}(); 
        token.approve(address(voting), 100);
        
        uint256 proposalId = voting.addProposal("Prop 1", "Desc", 5 ether, address(executor));
        
        // Stake 3 votos -> coste 9 tokens
        voting.stake(proposalId, 3);
        assertEq(token.balanceOf(user1), 91);

        // Retira 1 voto (Baja de 3 a 2 votos) -> Coste nuevo: 4 tokens. Debería reembolsar 5 tokens
        voting.withdrawFromProposal(proposalId, 1);
        (uint256 votes, uint256 tokensCost) = voting.votes(proposalId, user1);
        
        assertEq(votes, 2);
        assertEq(tokensCost, 4);
        assertEq(token.balanceOf(user1), 96); // 91 + 5
        
        vm.stopPrank();
    }

    /**
     * @notice Comprueba que la propuesta se ejecuta automáticamente al superar el umbral
     */
    function testThresholdAndAutomaticExecution() public {
        voting.openVoting{value: 10 ether}(); // Presupuesto = 10 ETH
        
        vm.startPrank(user1);
        voting.addParticipant{value: 1 ether}(); 
        token.approve(address(voting), 100);
        
        // Presupuesto pedido = 5 ETH
        uint256 proposalId = voting.addProposal("Funding", "Desc", 5 ether, address(executor));
        
        // Con 1 participante y 1 propuesta, la fórmula del umbral (en código) exige superar 1 voto.
        // Hacemos stake de 2 votos.
        voting.stake(proposalId, 2);
        
        // La propuesta debió ser aprobada y ejecutada
        QuadraticVoting.Proposal memory prop = voting.getProposalInfo(proposalId);
        assertTrue(prop.isApproved);
        
        // El ejecutor debió recibir los 5 ETH
        assertTrue(executor.executed());
        assertEq(executor.receivedAmount(), 5 ether);
        
        vm.stopPrank();
    }

    /**
     * @notice Testea la arquitectura Pull-over-Push (DoS Protection) al cerrar la votación
     */
    function testPullOverPushRefunds() public {
        voting.openVoting{value: 10 ether}();
        
        vm.startPrank(user1);
        voting.addParticipant{value: 1 ether}(); // 100 tokens
        token.approve(address(voting), 100);
        
        // Propuesta de signaling (0 budget). Estas NO se aprueban hasta que cierra la votación.
        uint256 proposalId = voting.addProposal("Signaling", "Desc", 0, address(executor));
        
        voting.stake(proposalId, 3); // Gasta 9 tokens
        assertEq(token.balanceOf(user1), 91);
        vm.stopPrank();
        
        // El admin cierra la votación
        voting.closeVoting();
        assertFalse(voting.votingOpen());
        
        // La propuesta de signaling se ejecuta manual o independientemente (Pull)
        voting.executeSignalingProposal(proposalId);
        assertTrue(executor.executed());
        
        // El usuario pide su reembolso de tokens (Pull)
        vm.startPrank(user1);
        voting.claimRefund(proposalId);
        
        // Recupera sus 9 tokens usados en la propuesta de signaling
        assertEq(token.balanceOf(user1), 100);
        vm.stopPrank();
    }
}