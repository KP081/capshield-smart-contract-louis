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
        assembly {
            if iszero(admin) {
                mstore(0x00, 0xd92e233d) // ZeroAddress()
                revert(0x1c, 0x04)
            }
            if iszero(_treasury) {
                mstore(0x00, 0xd92e233d) // ZeroAddress()
                revert(0x1c, 0x04)
            }
            if iszero(_dao) {
                mstore(0x00, 0xd92e233d) // ZeroAddress()
                revert(0x1c, 0x04)
            }
        }

        if (!_isContract(admin)) {
            assembly {
                mstore(0x00, 0xb597f865) // AdminMustBeContract()
                revert(0x1c, 0x04)
            }
        }

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
        assembly {
            if iszero(addr) {
                mstore(0x00, 0xd92e233d) // ZeroAddress()
                revert(0x1c, 0x04)
            }
        }
        _;
    }

    modifier validAmount(uint256 amount) {
        assembly {
            if iszero(amount) {
                mstore(0x00, 0x2c5211c6) // InvalidAmount()
                revert(0x1c, 0x04)
            }
        }
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
        uint256 newTotal;
        uint256 newTeamMinted;

        assembly {
            let currentTotal := sload(totalMinted.slot)

            // Check: totalMinted + amount <= MAX_SUPPLY
            newTotal := add(currentTotal, amount)
            if gt(newTotal, MAX_SUPPLY) {
                mstore(0x00, 0x8a164f63) // MaxSupplyExceeded()
                revert(0x1c, 0x04)
            }

            sstore(totalMinted.slot, newTotal)

            let teamSlot := mintAllocation.slot
            let currentTeam := sload(teamSlot)
            newTeamMinted := add(currentTeam, amount)
            sstore(teamSlot, newTeamMinted)
        }

        totalMinted = newTotal;
        mintAllocation.teamMinted = newTeamMinted;

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
        uint256 newTotal;
        uint256 newTreasuryMinted;

        assembly {
            let currentTotal := sload(totalMinted.slot)
            newTotal := add(currentTotal, amount)

            if gt(newTotal, MAX_SUPPLY) {
                mstore(0x00, 0x8a164f63) // MaxSupplyExceeded()
                revert(0x1c, 0x04)
            }

            sstore(totalMinted.slot, newTotal)

            // Update treasuryMinted (offset 1 in struct)
            let treasurySlot := add(mintAllocation.slot, 1)
            let currentTreasuryMint := sload(treasurySlot)
            newTreasuryMinted := add(currentTreasuryMint, amount)
            sstore(treasurySlot, newTreasuryMinted)
        }

        totalMinted = newTotal;
        mintAllocation.treasuryMinted = newTreasuryMinted;

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
        uint256 newTotal;
        uint256 newDaoMinted;

        assembly {
            let currentTotal := sload(totalMinted.slot)
            newTotal := add(currentTotal, amount)

            if gt(newTotal, MAX_SUPPLY) {
                mstore(0x00, 0x8a164f63) // MaxSupplyExceeded()
                revert(0x1c, 0x04)
            }

            sstore(totalMinted.slot, newTotal)

            // Update daoMinted (offset 2 in struct)
            let daoSlot := add(mintAllocation.slot, 2)
            let currentDaoMint := sload(daoSlot)
            newDaoMinted := add(currentDaoMint, amount)
            sstore(daoSlot, newDaoMinted)
        }

        totalMinted = newTotal;
        mintAllocation.daoMinted = newDaoMinted;

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
        uint256 tokensToMint;

        assembly {
            // Check revenue > 0
            if iszero(revenue) {
                mstore(0x00, 0xa34477b5) // InvalidRevenue()
                revert(0x1c, 0x04)
            }

            // Check marketValue > 0
            if iszero(marketValue) {
                mstore(0x00, 0x4ad34ed1) // InvalidMarketValue()
                revert(0x1c, 0x04)
            }

            // Calculate: tokensToMint = (revenue * 10^18) / marketValue
            let decimalss := 18
            let scaledRevenue := mul(revenue, exp(10, decimalss))
            tokensToMint := div(scaledRevenue, marketValue)

            // Check tokensToMint > 0
            if iszero(tokensToMint) {
                mstore(0x00, 0x2c5211c6) // InvalidAmount()
                revert(0x1c, 0x04)
            }

            // Check supply limit
            let currentTotal := sload(totalMinted.slot)
            let newTotal := add(currentTotal, tokensToMint)

            if gt(newTotal, MAX_SUPPLY) {
                mstore(0x00, 0x8a164f63) // MaxSupplyExceeded()
                revert(0x1c, 0x04)
            }

            // Update totalMinted
            sstore(totalMinted.slot, newTotal)
        }

        totalMinted += tokensToMint;
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
        if (!_isContract(newOwner)) {
            assembly {
                mstore(0x00, 0xb597f865) // AdminMustBeContract()
                revert(0x1c, 0x04)
            }
        }
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
        if (!_isContract(pendingOwner)) {
            assembly {
                mstore(0x00, 0xb597f865) // AdminMustBeContract()
                revert(0x1c, 0x04)
            }
        }
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
        assembly {
            if iszero(from) {
                mstore(0x00, 0xd92e233d) // ZeroAddress()
                revert(0x1c, 0x04)
            }
            if iszero(to) {
                mstore(0x00, 0xd92e233d) // ZeroAddress()
                revert(0x1c, 0x04)
            }
            if iszero(amount) {
                mstore(0x00, 0x2c5211c6) // InvalidAmount()
                revert(0x1c, 0x04)
            }
        }

        // Check exemptions
        bool fromExempt = exemptions[from];
        bool toExempt = exemptions[to];

        if (fromExempt || toExempt) {
            super._transfer(from, to, amount);
        } else {
            // Calculate fees using assembly for gas efficiency
            uint256 burnAmount;
            uint256 treasuryAmount;
            uint256 recipientAmount;

            assembly {
                // burnAmount = (amount * 1) / 100
                burnAmount := div(amount, FEE_DENOMINATOR)

                // treasuryAmount = (amount * 1) / 100
                treasuryAmount := div(amount, FEE_DENOMINATOR)

                // recipientAmount = amount - burnAmount - treasuryAmount
                recipientAmount := sub(amount, add(burnAmount, treasuryAmount))
            }

            // Burn tokens
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
