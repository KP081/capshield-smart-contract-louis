// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ICAPX {
    ///////////////// ERRORS /////////////////

    error ZeroAddress();
    error MaxSupplyExceeded();
    error InvalidAmount();
    error InvalidRevenue();
    error InvalidMarketValue();
    error MintAllocationExceeded();
    error AdminMustBeContract();

    ///////////////// EVENTS /////////////////

    event Mint(address indexed to, uint256 amount, uint256 indexed role);
    event RevenueMint(uint256 revenue, uint256 marketValue, uint256 tokensMinted);
    event TreasuryFee(address indexed from, address indexed to, uint256 amount);
    event TreasuryAddressUpdated(address indexed oldTreasury, address indexed newTreasury);
    event DaoAddressUpdated(address indexed oldDao, address indexed newDao);
    event ExemptionUpdated(address indexed account, bool exempt);
    event RoleGranted(uint256 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(uint256 indexed role, address indexed account, address indexed sender);
    event Burn(address indexed from, uint256 amount);

    ///////////////// STRUCTS /////////////////

    struct MintAllocation {
        uint256 teamMinted;
        uint256 treasuryMinted;
        uint256 daoMinted;
    }

    ///////////////// FUNCTIONS /////////////////

    function teamMint(address to, uint256 amount) external;

    function treasuryMint(address to, uint256 amount) external;

    function daoMint(address to, uint256 amount) external;

    function revenueMint(address to, uint256 revenue, uint256 marketValue) external;

    function setTreasuryAddress(address newTreasury) external;

    function setDaoAddress(address newDao) external;

    function setExemption(address account, bool exempt) external;

    function pause() external;

    function unpause() external;

    function getTreasuryAddress() external view returns (address);

    function getDaoAddress() external view returns (address);

    function isExempt(address account) external view returns (bool);

    function getMintAllocation() external view returns (MintAllocation memory);

    function getMaxSupply() external pure returns (uint256);
}
