// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IAngelSEED} from "./interfaces/IAngelSEED.sol";

/**
 * @title AngelSEED
 * @notice CAPShield Community Token (AngelSEED) - Community/Reward Token with role-based minting
 * @dev Implements BEP-20 (ERC20-compatible) token standard for BNB Smart Chain
 * @dev Built with Solady's gas-optimized ERC20 and OwnableRoles, plus OpenZeppelin's Pausable
 *
 * Features:
 * - Hard cap of 10 billion tokens
 * - Reward-based minting role
 * - No transfer fees (unlike CAPY)
 * - Pause/unpause functionality
 * - Burn mechanism (doesn't free mint capacity)
 * - Multisig-only admin
 */
contract AngelSEED is ERC20, OwnableRoles, Pausable, IAngelSEED {
    ///////////////// STATE VARIABLES /////////////////

    uint256 public constant REWARD_MINTER_ROLE = _ROLE_0;

    uint256 private constant MAX_SUPPLY = 10_000_000_000 * 10 ** 18; // 10 billion tokens

    uint256 public constant MAX_REASON_LENGTH = 256;

    uint256 private totalMinted;

    ///////////////// CONSTRUCTOR /////////////////

    /**
     * @notice Initializes the AngelSEED token with admin address
     * @param admin Address that will receive owner role (MUST be a multisig contract for production)
     * @dev Admin must be a contract (multisig) for security
     */
    constructor(address admin) {
        require(admin != address(0), ZeroAddress());

        // SECURITY: Enforce that admin is a contract (multisig), not an EOA
        require(_isContract(admin), AdminMustBeContract());

        _initializeOwner(admin);
        _grantRoles(admin, REWARD_MINTER_ROLE);

        emit RoleGranted(REWARD_MINTER_ROLE, admin, address(0));
    }

    ///////////////// MODIFIERS /////////////////

    modifier onlyRole(uint256 role) {
        require(hasAllRoles(msg.sender, role), Unauthorized());
        _;
    }

    ///////////////// MINTING FUNCTIONS /////////////////

    /**
     * @notice Mint tokens for community rewards
     * @param to Address to mint to
     * @param amount Amount of tokens to mint
     * @param reason Reason for minting
     * @dev Only callable by addresses with REWARD_MINTER_ROLE
     * @dev Respects MAX_SUPPLY cap
     */
    function rewardMint(
        address to,
        uint256 amount,
        string calldata reason
    ) external whenNotPaused onlyRole(REWARD_MINTER_ROLE) {
        require(to != address(0), ZeroAddress());
        require(amount > 0, InvalidAmount());
        require(totalMinted + amount <= MAX_SUPPLY, MaxSupplyExceeded());
        require(
            bytes(reason).length > 0 &&
                bytes(reason).length <= MAX_REASON_LENGTH,
            InvalidReason()
        );

        totalMinted = totalMinted + amount;
        _mint(to, amount);

        emit RewardMint(to, amount, reason);
    }

    function batchRewardMint(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string calldata reason
    ) external onlyRole(REWARD_MINTER_ROLE) whenNotPaused {
        require(recipients.length == amounts.length, ArrayLengthMismatch());
        require(recipients.length > 0, EmptyArrays());
        require(
            bytes(reason).length > 0 &&
                bytes(reason).length <= MAX_REASON_LENGTH,
            InvalidReason()
        );

        // Calculate total amount and validate all inputs first
        uint256 totalAmount;
        for (uint256 i; i < recipients.length; ) {
            require(recipients[i] != address(0), ZeroAddress());
            require(amounts[i] > 0, InvalidAmount());
            totalAmount += amounts[i];
            unchecked {
                ++i;
            }
        }

        // Check total amount against max supply
        require(totalMinted + totalAmount <= MAX_SUPPLY, MaxSupplyExceeded());
        totalMinted += totalAmount;

        // Perform minting
        for (uint256 i; i < recipients.length; ) {
            _mint(recipients[i], amounts[i]);
            emit RewardMint(recipients[i], amounts[i], reason);
            unchecked {
                ++i;
            }
        }
    }

    ///////////////// BURN FUNCTIONS /////////////////

    /**
     * @notice Burn tokens from caller's balance
     * @param amount Amount of tokens to burn
     * @dev Burning does not reduce totalMinted, so it doesn't free up mint capacity
     */
    function burn(uint256 amount) external {
        require(amount > 0, InvalidAmount());
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    /**
     * @notice Burn tokens from another address (requires allowance)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     * @dev Requires sufficient allowance from `from` address
     * @dev Burning does not reduce totalMinted, so it doesn't free up mint capacity
     */
    function burnFrom(address from, uint256 amount) external {
        require(from != address(0), ZeroAddress());
        require(amount > 0, InvalidAmount());

        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
        emit Burn(from, amount);
    }

    ///////////////// TRANSFER OVERRIDE /////////////////

    /**
     * @notice Transfer tokens to a specified address
     * @param to Address to transfer to
     * @param amount Amount to transfer
     * @dev Overridden to add pause functionality (no fees for AngelSEED)
     */
    function transfer(
        address to,
        uint256 amount
    ) public override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }

    /**
     * @notice Transfer tokens from one address to another
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount to transfer
     * @dev Overridden to add pause functionality (no fees for AngelSEED)
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    ///////////////// PAUSE FUNCTIONS /////////////////

    /**
     * @notice Pause all token transfers and minting
     * @dev Only callable by owner (multisig)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause all token transfers and minting
     * @dev Only callable by owner (multisig)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    ///////////////// ADMIN FUNCTIONS /////////////////

    /**
     * @notice Grant roles to an address
     * @param user Address to grant roles to
     * @param roles Roles to grant (as bitmap)
     * @dev Only callable by owner (multisig)
     */
    function grantRoles(
        address user,
        uint256 roles
    ) public payable override(IAngelSEED, OwnableRoles) onlyOwner {
        super.grantRoles(user, roles);
        emit RoleGranted(roles, user, msg.sender);
    }

    /**
     * @notice Revoke roles from an address
     * @param user Address to revoke roles from
     * @param roles Roles to revoke (as bitmap)
     * @dev Only callable by owner (multisig)
     */
    function revokeRoles(
        address user,
        uint256 roles
    ) public payable override(IAngelSEED, OwnableRoles) onlyOwner {
        super.revokeRoles(user, roles);
        emit RoleRevoked(roles, user, msg.sender);
    }

    ///////////////// OWNERSHIP FUNCTIONS /////////////////

    /**
     * @notice Transfer ownership to a new owner
     * @param newOwner Address of the new owner (MUST be a contract/multisig)
     * @dev Overrides Ownable's transferOwnership to enforce multisig requirement
     */
    function transferOwnership(
        address newOwner
    ) public payable override onlyOwner {
        require(_isContract(newOwner), AdminMustBeContract());
        super.transferOwnership(newOwner);
    }

    /**
     * @notice Complete the two-step ownership handover
     * @param pendingOwner Address of the pending owner (MUST be a contract/multisig)
     * @dev Overrides Ownable's completeOwnershipHandover to enforce multisig requirement
     */
    function completeOwnershipHandover(
        address pendingOwner
    ) public payable override onlyOwner {
        require(_isContract(pendingOwner), AdminMustBeContract());
        super.completeOwnershipHandover(pendingOwner);
    }

    /**
     * @notice Renounce ownership (disabled for security)
     * @dev Overridden to prevent accidental loss of ownership
     */
    function renounceOwnership() public payable override onlyOwner {
        revert("Ownership cannot be renounced");
    }

    ///////////////// GETTER FUNCTIONS /////////////////

    /**
     * @notice Returns the maximum supply cap
     */
    function getMaxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    /**
     * @notice Returns the total amount of tokens minted (including burned)
     * @dev Used to enforce hard cap - burning doesn't reduce this value
     */
    function getTotalMinted() external view returns (uint256) {
        return totalMinted;
    }

    /**
     * @notice Check if an address has a specific role
     * @param user Address to check
     * @param role Role to check (as bitmap)
     */
    function hasRole(uint256 role, address user) external view returns (bool) {
        return hasAllRoles(user, role);
    }

    /**
     * @notice Returns the default admin role identifier
     * @dev For compatibility with OpenZeppelin's AccessControl
     */
    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32) {
        return bytes32(0);
    }

    /**
     * @notice Check if the current owner is a contract (multisig)
     * @return True if owner is a contract, false if EOA
     * @dev This should always return true in production deployments
     */
    function isOwnerMultisig() external view returns (bool) {
        return _isContract(owner());
    }

    ///////////////// INTERNAL FUNCTIONS /////////////////

    /**
     * @notice Check if an address is a contract
     * @param account Address to check
     * @return True if the address has code (is a contract)
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    ///////////////// ERC20 METADATA /////////////////

    /**
     * @notice Returns the name of the token
     */
    function name() public pure override returns (string memory) {
        return "AngelSEED";
    }

    /**
     * @notice Returns the symbol of the token
     */
    function symbol() public pure override returns (string memory) {
        return "ANGEL";
    }
}
