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

        // exemptions[_treasury] = true;
        // exemptions[_dao] = true;

        assembly {
            let exemptionsSlot := exemptions.slot

            mstore(0x00, _treasury)
            mstore(0x20, exemptionsSlot)
            let exemptionsTSlot := keccak256(0x00, 0x40)
            sstore(exemptionsTSlot, 0x01)

            mstore(0x00, _dao)
            mstore(0x20, exemptionsSlot)
            let exemptionsDSlot := keccak256(0x00, 0x40)
            sstore(exemptionsDSlot, 0x01)

            // emit TreasuryAddressUpdated(address(0), _treasury);
            log3(
                0x00,
                0x00,
                0x430359a6d97ced2b6f93c77a91e7ce9dfd43252eb91e916adba170485cd8a6a4,
                0x0000000000000000000000000000000000000000,
                _treasury
            )

            // emit DaoAddressUpdated(address(0), _dao);
            log3(
                0x00,
                0x00,
                0x75b7fe723ac984bff13d3b320ed1a920035692e4a8e56fb2457774e7535c0d1d,
                0x0000000000000000000000000000000000000000,
                _dao
            )

            // emit ExemptionUpdated(_treasury, true);
            mstore(0x00, 0x01)
            log2(
                0x00,
                0x20,
                0x6c3adfee332544f29232690459f4fe23a1c9573efbaac65c9fc033355fb413f0,
                _treasury
            )

            // emit ExemptionUpdated(_dao, true);
            log2(
                0x00,
                0x20,
                0x6c3adfee332544f29232690459f4fe23a1c9573efbaac65c9fc033355fb413f0,
                _dao
            )

            // emit RoleGranted(TEAM_MINTER_ROLE, admin, address(0));
            log4(
                0x00,
                0x00,
                0x1ec1667fba5e43c5c76fff54e76d7a4a20a4fecf7b49724ad8d52a3f726e9dbd,
                TEAM_MINTER_ROLE,
                admin,
                0x0000000000000000000000000000000000000000
            )

            // emit RoleGranted(TREASURY_MINTER_ROLE, admin, address(0));
            log4(
                0x00,
                0x00,
                0x1ec1667fba5e43c5c76fff54e76d7a4a20a4fecf7b49724ad8d52a3f726e9dbd,
                TREASURY_MINTER_ROLE,
                admin,
                0x0000000000000000000000000000000000000000
            )

            // emit RoleGranted(DAO_MINTER_ROLE, admin, address(0));
            log4(
                0x00,
                0x00,
                0x1ec1667fba5e43c5c76fff54e76d7a4a20a4fecf7b49724ad8d52a3f726e9dbd,
                DAO_MINTER_ROLE,
                admin,
                0x0000000000000000000000000000000000000000
            )
        }
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

        // totalMinted = newTotal;
        // mintAllocation.teamMinted = newTeamMinted;

        assembly {
            let totalMintedSlot := totalMinted.slot
            let currentTotal := sload(totalMintedSlot)

            // Check: totalMinted + amount <= MAX_SUPPLY
            newTotal := add(currentTotal, amount)
            if gt(newTotal, MAX_SUPPLY) {
                mstore(0x00, 0x8a164f63) // MaxSupplyExceeded()
                revert(0x1c, 0x04)
            }

            sstore(totalMintedSlot, newTotal)

            let teamSlot := mintAllocation.slot
            let currentTeam := sload(teamSlot)
            newTeamMinted := add(currentTeam, amount)
            sstore(teamSlot, newTeamMinted)
        }

        _mint(to, amount);

        assembly {
            // emit Mint(to, amount, TEAM_MINTER_ROLE);
            mstore(0x00, amount)
            log3(
                0x00,
                0x20,
                0x4c209b5fc8ad50758f13e2e1088ba56a560dff690a1c6fef26394f4c03821c4f,
                to,
                TEAM_MINTER_ROLE
            )
        }
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

        // totalMinted = newTotal;
        // mintAllocation.treasuryMinted = newTreasuryMinted;

        assembly {
            let totalMintedSlot := totalMinted.slot
            let currentTotal := sload(totalMintedSlot)
            newTotal := add(currentTotal, amount)

            if gt(newTotal, MAX_SUPPLY) {
                mstore(0x00, 0x8a164f63) // MaxSupplyExceeded()
                revert(0x1c, 0x04)
            }

            sstore(totalMintedSlot, newTotal)

            // Update treasuryMinted (offset 1 in struct)
            let treasurySlot := add(mintAllocation.slot, 1)
            let currentTreasuryMint := sload(treasurySlot)
            newTreasuryMinted := add(currentTreasuryMint, amount)
            sstore(treasurySlot, newTreasuryMinted)
        }

        _mint(to, amount);

        assembly {
            // emit Mint(to, amount, TREASURY_MINTER_ROLE);
            mstore(0x00, amount)
            log3(
                0x00,
                0x20,
                0x4c209b5fc8ad50758f13e2e1088ba56a560dff690a1c6fef26394f4c03821c4f,
                to,
                TREASURY_MINTER_ROLE
            )
        }
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

        // totalMinted = newTotal;
        // mintAllocation.daoMinted = newDaoMinted;

        assembly {
            let totalMintedSlot := totalMinted.slot
            let currentTotal := sload(totalMintedSlot)
            newTotal := add(currentTotal, amount)

            if gt(newTotal, MAX_SUPPLY) {
                mstore(0x00, 0x8a164f63) // MaxSupplyExceeded()
                revert(0x1c, 0x04)
            }

            sstore(totalMintedSlot, newTotal)

            // Update daoMinted (offset 2 in struct)
            let daoSlot := add(mintAllocation.slot, 2)
            let currentDaoMint := sload(daoSlot)
            newDaoMinted := add(currentDaoMint, amount)
            sstore(daoSlot, newDaoMinted)
        }

        _mint(to, amount);

        assembly {
            // emit Mint(to, amount, DAO_MINTER_ROLE);
            mstore(0x00, amount)
            log3(
                0x00,
                0x20,
                0x4c209b5fc8ad50758f13e2e1088ba56a560dff690a1c6fef26394f4c03821c4f,
                to,
                DAO_MINTER_ROLE
            )
        }
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

            // totalMinted += tokensToMint;
            // Update totalMinted
            sstore(totalMinted.slot, newTotal)
        }

        _mint(to, tokensToMint);

        assembly {
            // emit RevenueMint(revenue, marketValue, tokensToMint);
            mstore(0x00, revenue)
            mstore(0x20, marketValue)
            mstore(0x40, tokensToMint)

            log1(
                0x00,
                0x60,
                0xa2873c389c7faf6dc0b7d62bb1e3f2a07e31219d74ab22a42c3278ee693734ee
            )
        }
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

        assembly {
            let exemptionsSlot := exemptions.slot

            // exemptions[oldTreasury] = false;
            mstore(0x00, oldTreasury)
            mstore(0x20, exemptionsSlot)
            let exemptionsOTSlot := keccak256(0x00, 0x40)
            sstore(exemptionsOTSlot, 0x00)

            // exemptions[newTreasury] = true;
            mstore(0x00, newTreasury)
            mstore(0x20, exemptionsSlot)
            let exemptionsNTSlot := keccak256(0x00, 0x40)
            sstore(exemptionsNTSlot, 0x01)

            // emit TreasuryAddressUpdated(oldTreasury, newTreasury);
            log3(
                0x00,
                0x00,
                0x430359a6d97ced2b6f93c77a91e7ce9dfd43252eb91e916adba170485cd8a6a4,
                oldTreasury,
                newTreasury
            )

            // emit ExemptionUpdated(oldTreasury, false);
            mstore(0x00, 0x00)
            log2(
                0x00,
                0x20,
                0x6c3adfee332544f29232690459f4fe23a1c9573efbaac65c9fc033355fb413f0,
                oldTreasury
            )

            // emit ExemptionUpdated(newTreasury, true);
            mstore(0x00, 0x01)
            log2(
                0x00,
                0x20,
                0x6c3adfee332544f29232690459f4fe23a1c9573efbaac65c9fc033355fb413f0,
                newTreasury
            )
        }
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

        assembly {
            let exemptionsSlot := exemptions.slot

            // exemptions[oldDao] = false;
            mstore(0x00, oldDao)
            mstore(0x20, exemptionsSlot)
            let exemptionsODSlot := keccak256(0x00, 0x40)
            sstore(exemptionsODSlot, 0x00)

            // exemptions[newDao] = true;
            mstore(0x00, newDao)
            mstore(0x20, exemptionsSlot)
            let exemptionsNDSlot := keccak256(0x00, 0x40)
            sstore(exemptionsNDSlot, 0x01)

            // emit DaoAddressUpdated(oldDao, newDao);
            log3(
                0x00,
                0x00,
                0x75b7fe723ac984bff13d3b320ed1a920035692e4a8e56fb2457774e7535c0d1d,
                oldDao,
                newDao
            )

            // emit ExemptionUpdated(oldDao, false);
            mstore(0x00, 0x00)
            log2(
                0x00,
                0x20,
                0x6c3adfee332544f29232690459f4fe23a1c9573efbaac65c9fc033355fb413f0,
                oldDao
            )

            // emit ExemptionUpdated(newDao, true);
            mstore(0x00, 0x01)
            log2(
                0x00,
                0x20,
                0x6c3adfee332544f29232690459f4fe23a1c9573efbaac65c9fc033355fb413f0,
                newDao
            )
        }
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
        assembly {
            // exemptions[account] = exempt;
            let exemptionsSlot := exemptions.slot

            mstore(0x00, account)
            mstore(0x20, exemptionsSlot)
            let slot := keccak256(0x00, 0x40)

            sstore(slot, exempt)

            // emit ExemptionUpdated(account, exempt);
            mstore(0x00, exempt)
            log2(
                0x00,
                0x20,
                0x6c3adfee332544f29232690459f4fe23a1c9573efbaac65c9fc033355fb413f0,
                account
            )
        }
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

        assembly {
            // emit Burn(msg.sender, amount);
            mstore(0x00, amount)
            log2(
                0x00,
                0x20,
                0xcc16f5dbb4873280815c1ee09dbd06736cffcc184412cf7a71a0fdb75d397ca5,
                caller()
            )
        }
    }

    /**
     * @notice Burns tokens from specified address (requires allowance)
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burnFrom(address from, uint256 amount) external {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);

        assembly {
            // emit Burn(from, amount);
            mstore(0x00, amount)
            log2(
                0x00,
                0x20,
                0xcc16f5dbb4873280815c1ee09dbd06736cffcc184412cf7a71a0fdb75d397ca5,
                from
            )
        }
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

        assembly {
            // emit RoleGranted(roles, user, msg.sender);
            log4(
                0x00,
                0x00,
                0x1ec1667fba5e43c5c76fff54e76d7a4a20a4fecf7b49724ad8d52a3f726e9dbd,
                roles,
                user,
                caller()
            )
        }
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

        assembly {
            // emit RoleRevoked(roles, user, msg.sender);
            log4(
                0x00,
                0x00,
                0xe0df21b65c73c27081b8f042a012b124085b41d78d27b7e3c4780f5650f5ebb8,
                roles,
                user,
                caller()
            )
        }
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
