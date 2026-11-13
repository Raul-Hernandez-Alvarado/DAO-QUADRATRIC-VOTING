// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VotingToken
 * @notice ERC20 token utilizado para la votación cuadrática. Solo el contrato QuadraticVoting puede mintear o quemar.
 */
contract VotingToken is ERC20, Ownable {
    
    uint256 public immutable maxSupply;

    error MaxSupplyExceeded();

    /**
     * @notice Inicializa el token de votación
     * @param name_ Nombre del token
     * @param symbol_ Símbolo del token
     * @param maxSupply_ Suministro máximo permitido
     * @param initialOwner_ Dirección del contrato QuadraticVoting que será el dueño
     */
    constructor(
        string memory name_, 
        string memory symbol_, 
        uint256 maxSupply_,
        address initialOwner_
    ) 
        ERC20(name_, symbol_) 
        Ownable(initialOwner_)
    {
        maxSupply = maxSupply_;
    }
    
    /**
     * @notice Mintea nuevos tokens a un participante
     * @param account Dirección del participante que recibe los tokens
     * @param amount Cantidad de tokens a mintear
     */
    function mint(address account, uint256 amount) external onlyOwner {
        if (totalSupply() + amount > maxSupply) revert MaxSupplyExceeded();
        _mint(account, amount);
    }
    
    /**
     * @notice Quema tokens del balance del contrato de votación
     * @param amount Cantidad de tokens a quemar
     */
    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }
}