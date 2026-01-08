// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ICAPX} from "./interfaces/ICAPX.sol";

/**
 * @title CAPX
 * @notice CAPShield Token (CAPX) - Shield Token with role-based minting, transfer fees, and revenue-based minting
 * @dev Implements BEP-20 (ERC20-compatible) token standard for BNB Smart Chain
 * @dev Built with Solady's gas-optimized ERC20 and OwnableRoles, plus OpenZeppelin's Pausable
 *
 * Features:
 * - Hard cap of 100M tokens
 * - Role-based minting (Team, Treasury, DAO)
 * - Revenue-based minting formula: tokensToMint = revenue / marketValue
 * - Transfer hooks: 1% burn + 1% treasury fee (98% to recipient)
 * - Exemptions for Treasury and DAO addresses
 * - Pause/unpause functionality
 * - Burn mechanism
 * - Multisig-only admin
 */
contract CAPX is ERC20, OwnableRoles, Pausable, ICAPX {
    ///////////////// STATE VARIABLES /////////////////

    uint256 public constant TEAM_MINTER_ROLE = _ROLE_0;
    uint256 public constant TREASURY_MINTER_ROLE = _ROLE_1;
    uint256 public constant DAO_MINTER_ROLE = _ROLE_2;

    uint256 private constant MAX_SUPPLY = 100_000_000 * 10 ** 18;
    uint256 private constant BURN_FEE_PERCENT = 1;
    uint256 private constant TREASURY_FEE_PERCENT = 1;
    uint256 private constant FEE_DENOMINATOR = 100;

    address private treasury;
    address private dao;
    uint256 private totalMinted;

    ///////////////// MAPPINGS /////////////////

    mapping(address account => bool exempt) private exemptions;

    MintAllocation private mintAllocation;

    ///////////////// CONSTRUCTOR /////////////////

    /**
     * @notice Initializes the CAPX token with admin, treasury, and DAO addresses
     * @param admin Address that will receive owner role (MUST be a multisig contract for production)
     * @param _treasury Treasury address for fee collection
     * @param _dao DAO address for governance
     * @dev IMPORTANT: For production deployment, admin MUST be a multisig contract (e.g., Gnosis Safe)
     *      to prevent single point of failure. The constructor checks this requirement.
     */
    constructor(address admin, address _treasury, address _dao) {
        // require(admin != address(0), ZeroAddress());
        // require(_treasury != address(0), ZeroAddress());
        // require(_dao != address(0), ZeroAddress());

        if (admin == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();
        if (_dao == address(0)) revert ZeroAddress();

        // Enforce that admin is a contract (multisig), not an EOA
        // This prevents single EOA from having full control over the token
        // require(_isContract(admin), AdminMustBeContract());

        if (!_isContract(admin)) revert AdminMustBeContract();

        _initializeOwner(admin);
        _grantRoles(
            admin,
            TEAM_MINTER_ROLE | TREASURY_MINTER_ROLE | DAO_MINTER_ROLE
        );

        treasury = _treasury;
        dao = _dao;

        exemptions[_treasury] = true;
        exemptions[_dao] = true;

        emit TreasuryAddressUpdated(address(0), _treasury);
        emit DaoAddressUpdated(address(0), _dao);
        emit ExemptionUpdated(_treasury, true);
        emit ExemptionUpdated(_dao, true);
        emit RoleGranted(TEAM_MINTER_ROLE, admin, address(0));
        emit RoleGranted(TREASURY_MINTER_ROLE, admin, address(0));
        emit RoleGranted(DAO_MINTER_ROLE, admin, address(0));
    }

    ///////////////// MODIFIERS /////////////////

    modifier validAddress(address addr) {
        // require(addr != address(0), ZeroAddress());
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    modifier validAmount(uint256 amount) {
        // require(amount > 0, InvalidAmount());
        if(amount <= 0) revert InvalidAmount();
        _;
    }

    ///////////////// ERC20 OVERRIDES /////////////////

    /**
     * @notice Returns the name of the token
     */
    function name() public pure override returns (string memory) {
        return "CAPShield";
    }

    /**
     * @notice Returns the symbol of the token
     */
    function symbol() public pure override returns (string memory) {
        return "CAPX";
    }

    ///////////////// MINTING FUNCTIONS /////////////////

    /**
     * @notice Mints tokens for team allocation
     * @param to Recipient address
     * @param amount Amount to mint
     * @dev Only TEAM_MINTER_ROLE can call. Respects MAX_SUPPLY cap.
     */
    function teamMint(
        address to,
        uint256 amount
    )
        external
        onlyRoles(TEAM_MINTER_ROLE)
        whenNotPaused
        validAddress(to)
        validAmount(amount)
    {
        // require(totalMinted + amount <= MAX_SUPPLY, MaxSupplyExceeded());
        if (totalMinted + amount > MAX_SUPPLY) revert MaxSupplyExceeded();

        totalMinted = totalMinted + amount;
        mintAllocation.teamMinted = mintAllocation.teamMinted + amount;

        _mint(to, amount);

        emit Mint(to, amount, TEAM_MINTER_ROLE);
    }

    /**
     * @notice Mints tokens for treasury allocation
     * @param to Recipient address
     * @param amount Amount to mint
     * @dev Only TREASURY_MINTER_ROLE can call. Respects MAX_SUPPLY cap.
     */
    function treasuryMint(
        address to,
        uint256 amount
    )
        external
        onlyRoles(TREASURY_MINTER_ROLE)
        whenNotPaused
        validAddress(to)
        validAmount(amount)
    {
        // require(totalMinted + amount <= MAX_SUPPLY, MaxSupplyExceeded());
        if (totalMinted + amount > MAX_SUPPLY) revert MaxSupplyExceeded();

        totalMinted = totalMinted + amount;
        mintAllocation.treasuryMinted = mintAllocation.treasuryMinted + amount;
        _mint(to, amount);

        emit Mint(to, amount, TREASURY_MINTER_ROLE);
    }

    /**
     * @notice Mints tokens for DAO allocation
     * @param to Recipient address
     * @param amount Amount to mint
     * @dev Only DAO_MINTER_ROLE can call. Respects MAX_SUPPLY cap.
     */
    function daoMint(
        address to,
        uint256 amount
    )
        external
        onlyRoles(DAO_MINTER_ROLE)
        whenNotPaused
        validAddress(to)
        validAmount(amount)
    {
        // require(totalMinted + amount <= MAX_SUPPLY, MaxSupplyExceeded());
        if (totalMinted + amount > MAX_SUPPLY) revert MaxSupplyExceeded();

        totalMinted = totalMinted + amount;
        mintAllocation.daoMinted = mintAllocation.daoMinted + amount;
        _mint(to, amount);

        emit Mint(to, amount, DAO_MINTER_ROLE);
    }

    /**
     * @notice Mints tokens based on revenue and market value
     * @param to Address to mint tokens to
     * @param revenue Revenue amount in wei
     * @param marketValue Market value per token in wei
     * @dev Formula: tokensToMint = revenue / marketValue
     *      Only owner can call. Respects MAX_SUPPLY cap.
     */
    function revenueMint(
        address to,
        uint256 revenue,
        uint256 marketValue
    ) external onlyOwner whenNotPaused validAddress(to) {
        // require(revenue > 0, InvalidRevenue());
        // require(marketValue > 0, InvalidMarketValue());
        if (revenue <= 0) revert InvalidRevenue();
        if (marketValue <= 0) revert InvalidMarketValue();

        uint256 tokensToMint = (revenue * 10 ** decimals()) / marketValue;
        // require(tokensToMint > 0, InvalidAmount());
        // require(totalMinted + tokensToMint <= MAX_SUPPLY, MaxSupplyExceeded());
        if (tokensToMint <= 0) revert InvalidAmount();
        if (totalMinted + tokensToMint > MAX_SUPPLY) revert MaxSupplyExceeded();

        totalMinted = totalMinted + tokensToMint;
        _mint(to, tokensToMint);

        emit RevenueMint(revenue, marketValue, tokensToMint);
    }

    ///////////////// ADMIN FUNCTIONS /////////////////

    /**
     * @notice Updates the treasury address
     * @param newTreasury New treasury address
     * @dev Only owner can call. Automatically exempts new treasury.
     */
    function setTreasuryAddress(
        address newTreasury
    ) external onlyOwner validAddress(newTreasury) {
        address oldTreasury = treasury;
        treasury = newTreasury;

        exemptions[oldTreasury] = false;
        exemptions[newTreasury] = true;

        emit TreasuryAddressUpdated(oldTreasury, newTreasury);
        emit ExemptionUpdated(oldTreasury, false);
        emit ExemptionUpdated(newTreasury, true);
    }

    /**
     * @notice Updates the DAO address
     * @param newDao New DAO address
     * @dev Only owner can call. Automatically exempts new DAO.
     */
    function setDaoAddress(
        address newDao
    ) external onlyOwner validAddress(newDao) {
        address oldDao = dao;
        dao = newDao;

        exemptions[oldDao] = false;
        exemptions[newDao] = true;

        emit DaoAddressUpdated(oldDao, newDao);
        emit ExemptionUpdated(oldDao, false);
        emit ExemptionUpdated(newDao, true);
    }

    /**
     * @notice Sets fee exemption status for an address
     * @param account Address to update
     * @param exempt Exemption status
     * @dev Only owner can call.
     */
    function setExemption(
        address account,
        bool exempt
    ) external onlyOwner validAddress(account) {
        exemptions[account] = exempt;
        emit ExemptionUpdated(account, exempt);
    }

    /**
     * @notice Pauses all token transfers and minting
     * @dev Only owner can call.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses token transfers and minting
     * @dev Only owner can call.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Override transfer to add fee logic
     */
    function transfer(
        address to,
        uint256 amount
    ) public override whenNotPaused returns (bool) {
        _applyTransferWithFees(msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Override transferFrom to add fee logic
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override whenNotPaused returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _applyTransferWithFees(from, to, amount);
        return true;
    }

    /**
     * @notice Burns tokens from caller's balance
     * @param amount Amount to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    /**
     * @notice Burns tokens from specified address (requires allowance)
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burnFrom(address from, uint256 amount) external {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
        emit Burn(from, amount);
    }

    /**
     * @notice Grant roles to an address
     * @param user Address to grant roles to
     * @param roles Roles to grant (as bitmap)
     */
    function grantRoles(
        address user,
        uint256 roles
    ) public payable override onlyOwner {
        super.grantRoles(user, roles);
        emit RoleGranted(roles, user, msg.sender);
    }

    /**
     * @notice Revoke roles from an address
     * @param user Address to revoke roles from
     * @param roles Roles to revoke (as bitmap)
     */
    function revokeRoles(
        address user,
        uint256 roles
    ) public payable override onlyOwner {
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
        // require(_isContract(newOwner), AdminMustBeContract());
        if (!_isContract(newOwner)) revert AdminMustBeContract();
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
        // require(_isContract(pendingOwner), AdminMustBeContract());
        if (!_isContract(pendingOwner)) revert AdminMustBeContract();
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
     * @notice Returns the current treasury address
     */
    function getTreasuryAddress() external view returns (address) {
        return treasury;
    }

    /**
     * @notice Returns the current DAO address
     */
    function getDaoAddress() external view returns (address) {
        return dao;
    }

    /**
     * @notice Checks if an address is exempt from transfer fees
     * @param account Address to check
     */
    function isExempt(address account) external view returns (bool) {
        return exemptions[account];
    }

    /**
     * @notice Returns the mint allocation stats
     */
    function getMintAllocation() external view returns (MintAllocation memory) {
        return mintAllocation;
    }

    /**
     * @notice Returns the maximum supply cap
     */
    function getMaxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
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

    /**
     * @notice Internal function to apply transfer with fees
     * @dev Applies 1% burn + 1% treasury fee unless sender or recipient is exempt
     *      Exempt transfers bypass all fee logic
     */
    function _applyTransferWithFees(
        address from,
        address to,
        uint256 amount
    ) internal {
        // require(from != address(0), ZeroAddress());
        // require(to != address(0), ZeroAddress());
        // require(amount > 0, InvalidAmount());
        if (from == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        if (amount <= 0) revert InvalidAmount();

        // Check if either sender or recipient is exempt
        if (exemptions[from] || exemptions[to]) {
            // Exempt transfer - no fees
            super._transfer(from, to, amount);
        } else {
            // Calculate fees
            uint256 burnAmount = (amount * BURN_FEE_PERCENT) / FEE_DENOMINATOR;
            uint256 treasuryAmount = (amount * TREASURY_FEE_PERCENT) /
                FEE_DENOMINATOR;
            uint256 recipientAmount = amount - burnAmount - treasuryAmount;

            // Burn tokens (reduce supply)
            if (burnAmount > 0) {
                _burn(from, burnAmount);
            }

            // Transfer to treasury
            if (treasuryAmount > 0) {
                super._transfer(from, treasury, treasuryAmount);
                emit TreasuryFee(from, treasury, treasuryAmount);
            }

            // Transfer to recipient
            super._transfer(from, to, recipientAmount);
        }
    }
}
