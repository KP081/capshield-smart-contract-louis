const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("CAPX Token", function () {
  async function deployTokenFixture() {
    const [
      adminSigner,
      treasury,
      dao,
      teamMinter,
      treasuryMinter,
      daoMinter,
      user1,
      user2,
      user3,
    ] = await ethers.getSigners();

    // Deploy MockMultisig to act as admin (satisfies contract requirement)
    const MockMultisig = await ethers.getContractFactory("MockMultisig");
    const multisig = await MockMultisig.deploy(adminSigner.address);

    const CAPX = await ethers.getContractFactory("CAPX");
    const capy = await CAPX.deploy(
      multisig.target,
      treasury.address,
      dao.address
    );

    // Get role identifiers
    const DEFAULT_ADMIN_ROLE = await capy.DEFAULT_ADMIN_ROLE();
    const TEAM_MINTER_ROLE = await capy.TEAM_MINTER_ROLE();
    const TREASURY_MINTER_ROLE = await capy.TREASURY_MINTER_ROLE();
    const DAO_MINTER_ROLE = await capy.DAO_MINTER_ROLE();

    // Helper function to execute CAPY functions through the multisig
    const executeAsAdmin = async (functionName, ...args) => {
      const data = capy.interface.encodeFunctionData(functionName, args);
      return multisig.connect(adminSigner).execute(capy.target, data);
    };

    // Create wrapper for capy.connect(admin) pattern
    // When tests call capy.connect(admin).function(), it will execute through multisig
    const originalConnect = capy.connect.bind(capy);
    capy.connect = (signer) => {
      // If connecting as admin (multisig), return wrapped contract
      if (signer && signer.address === multisig.target) {
        return {
          teamMint: (to, amount) => executeAsAdmin("teamMint", to, amount),
          treasuryMint: (to, amount) =>
            executeAsAdmin("treasuryMint", to, amount),
          daoMint: (to, amount) => executeAsAdmin("daoMint", to, amount),
          revenueMint: (to, revenue, marketValue) =>
            executeAsAdmin("revenueMint", to, revenue, marketValue),
          grantRoles: (user, roles) =>
            executeAsAdmin("grantRoles", user, roles),
          revokeRoles: (user, roles) =>
            executeAsAdmin("revokeRoles", user, roles),
          pause: () => executeAsAdmin("pause"),
          unpause: () => executeAsAdmin("unpause"),
          setTreasuryAddress: (addr) =>
            executeAsAdmin("setTreasuryAddress", addr),
          setDaoAddress: (addr) => executeAsAdmin("setDaoAddress", addr),
          setExemption: (account, exempt) =>
            executeAsAdmin("setExemption", account, exempt),
        };
      }
      // Otherwise use original connect
      return originalConnect(signer);
    };

    // Create admin object with address property
    const admin = {
      address: multisig.target,
    };

    return {
      capy,
      admin,
      adminSigner,
      executeAsAdmin,
      treasury,
      dao,
      teamMinter,
      treasuryMinter,
      daoMinter,
      user1,
      user2,
      user3,
      DEFAULT_ADMIN_ROLE,
      TEAM_MINTER_ROLE,
      TREASURY_MINTER_ROLE,
      DAO_MINTER_ROLE,
    };
  }

  describe("1. Deployment & Initial State", function () {
    it("Should have correct name, symbol, and decimals", async function () {
      const { capy } = await loadFixture(deployTokenFixture);

      expect(await capy.name()).to.equal("CAPShield");
      expect(await capy.symbol()).to.equal("CAPX");
      expect(await capy.decimals()).to.equal(18);
    });

    it("Should start with totalSupply = 0", async function () {
      const { capy } = await loadFixture(deployTokenFixture);

      expect(await capy.totalSupply()).to.equal(0);
    });

    it("Should have MAX_SUPPLY enforced", async function () {
      const { capy } = await loadFixture(deployTokenFixture);

      const maxSupply = await capy.getMaxSupply();
      expect(maxSupply).to.equal(ethers.parseUnits("100000000", 18));
    });

    it("Should have treasury and DAO addresses set", async function () {
      const { capy, treasury, dao } = await loadFixture(deployTokenFixture);

      expect(await capy.getTreasuryAddress()).to.equal(treasury.address);
      expect(await capy.getDaoAddress()).to.equal(dao.address);
    });

    it("Should start unpaused", async function () {
      const { capy } = await loadFixture(deployTokenFixture);

      expect(await capy.paused()).to.equal(false);
    });

    it("Should exempt treasury and DAO from fees", async function () {
      const { capy, treasury, dao } = await loadFixture(deployTokenFixture);

      expect(await capy.isExempt(treasury.address)).to.equal(true);
      expect(await capy.isExempt(dao.address)).to.equal(true);
    });

    it("Should enforce admin is a contract (multisig)", async function () {
      const { capy } = await loadFixture(deployTokenFixture);

      // Verify the owner is a contract (multisig)
      expect(await capy.isOwnerMultisig()).to.equal(true);
    });

    it("Should revert if admin is an EOA during deployment", async function () {
      const [eoaAdmin, treasury, dao] = await ethers.getSigners();

      const CAPX = await ethers.getContractFactory("CAPX");

      // Should revert because eoaAdmin is not a contract
      await expect(
        CAPX.deploy(eoaAdmin.address, treasury.address, dao.address)
      ).to.be.revertedWithCustomError(CAPX, "AdminMustBeContract");
    });
  });

  describe("2. Access Control", function () {
    it("Should assign DEFAULT_ADMIN_ROLE to admin (multisig)", async function () {
      const { capy, admin, DEFAULT_ADMIN_ROLE } = await loadFixture(
        deployTokenFixture
      );

      expect(await capy.hasRole(DEFAULT_ADMIN_ROLE, admin.address)).to.equal(
        true
      );
    });

    it("Should assign TEAM_MINTER_ROLE, TREASURY_MINTER_ROLE, DAO_MINTER_ROLE", async function () {
      const {
        capy,
        admin,
        TEAM_MINTER_ROLE,
        TREASURY_MINTER_ROLE,
        DAO_MINTER_ROLE,
      } = await loadFixture(deployTokenFixture);

      expect(await capy.hasRole(TEAM_MINTER_ROLE, admin.address)).to.equal(
        true
      );
      expect(await capy.hasRole(TREASURY_MINTER_ROLE, admin.address)).to.equal(
        true
      );
      expect(await capy.hasRole(DAO_MINTER_ROLE, admin.address)).to.equal(true);
    });

    it("Should prevent unauthorized users from minting", async function () {
      const { capy, user1 } = await loadFixture(deployTokenFixture);

      const amount = ethers.parseUnits("1000", 18);

      await expect(capy.connect(user1).teamMint(user1.address, amount)).to.be
        .reverted;
      await expect(capy.connect(user1).treasuryMint(user1.address, amount)).to
        .be.reverted;
      await expect(capy.connect(user1).daoMint(user1.address, amount)).to.be
        .reverted;
    });

    it("Should allow admin to grant and revoke roles", async function () {
      const { capy, executeAsAdmin, user1, TEAM_MINTER_ROLE } =
        await loadFixture(deployTokenFixture);

      await executeAsAdmin("grantRoles", user1.address, TEAM_MINTER_ROLE);
      expect(await capy.hasRole(TEAM_MINTER_ROLE, user1.address)).to.equal(
        true
      );

      await executeAsAdmin("revokeRoles", user1.address, TEAM_MINTER_ROLE);
      expect(await capy.hasRole(TEAM_MINTER_ROLE, user1.address)).to.equal(
        false
      );
    });
  });

  describe("3. Hard Cap Enforcement", function () {
    it("Should allow minting up to cap", async function () {
      const { capy, admin, user1 } = await loadFixture(deployTokenFixture);

      const maxSupply = await capy.getMaxSupply();
      await capy.connect(admin).teamMint(user1.address, maxSupply);

      expect(await capy.totalSupply()).to.equal(maxSupply);
    });

    it("Should revert when minting above cap", async function () {
      const { capy, admin, user1 } = await loadFixture(deployTokenFixture);

      const maxSupply = await capy.getMaxSupply();
      const overAmount = maxSupply + 1n;

      await expect(
        capy.connect(admin).teamMint(user1.address, overAmount)
      ).to.be.revertedWithCustomError(capy, "MaxSupplyExceeded");
    });

    it("Should prevent revenue mint from exceeding cap", async function () {
      const { capy, admin, user1 } = await loadFixture(deployTokenFixture);

      const maxSupply = await capy.getMaxSupply();
      const almostCap = maxSupply - ethers.parseUnits("50", 18);

      // Mint almost to cap
      await capy.connect(admin).teamMint(user1.address, almostCap);

      // Try revenue mint that would exceed cap (1000 tokens when only 50 left)
      // Revenue of 1000 tokens with market value of 1 wei = 1000 tokens minted
      const revenue = ethers.parseUnits("1000", 18); // 1000 tokens worth of revenue
      const marketValue = 1n; // 1 wei per token

      await expect(
        capy.connect(admin).revenueMint(user1.address, revenue, marketValue)
      ).to.be.revertedWithCustomError(capy, "MaxSupplyExceeded");
    });

    it("Should confirm burn does not free mint capacity", async function () {
      const { capy, admin, user1 } = await loadFixture(deployTokenFixture);

      const maxSupply = await capy.getMaxSupply();

      // Mint to cap
      await capy.connect(admin).teamMint(user1.address, maxSupply);

      // Burn some tokens
      const burnAmount = ethers.parseUnits("1000000", 18);
      await capy.connect(user1).burn(burnAmount);

      // Try to mint again - should still fail
      await expect(
        capy.connect(admin).teamMint(user1.address, 1)
      ).to.be.revertedWithCustomError(capy, "MaxSupplyExceeded");
    });
  });

  describe("4. Role-Based Minting", function () {
    it("Should allow team mint within allocation", async function () {
      const { capy, admin, user1 } = await loadFixture(deployTokenFixture);

      const amount = ethers.parseUnits("10000000", 18);

      await expect(capy.connect(admin).teamMint(user1.address, amount))
        .to.emit(capy, "Mint")
        .withArgs(user1.address, amount, await capy.TEAM_MINTER_ROLE());

      expect(await capy.balanceOf(user1.address)).to.equal(amount);

      const allocation = await capy.getMintAllocation();
      expect(allocation.teamMinted).to.equal(amount);
    });

    it("Should allow treasury mint within cap", async function () {
      const { capy, admin, user1 } = await loadFixture(deployTokenFixture);

      const amount = ethers.parseUnits("15000000", 18);

      await expect(capy.connect(admin).treasuryMint(user1.address, amount))
        .to.emit(capy, "Mint")
        .withArgs(user1.address, amount, await capy.TREASURY_MINTER_ROLE());

      expect(await capy.balanceOf(user1.address)).to.equal(amount);

      const allocation = await capy.getMintAllocation();
      expect(allocation.treasuryMinted).to.equal(amount);
    });

    it("Should allow DAO mint within cap", async function () {
      const { capy, admin, user1 } = await loadFixture(deployTokenFixture);

      const amount = ethers.parseUnits("25000000", 18);

      await expect(capy.connect(admin).daoMint(user1.address, amount))
        .to.emit(capy, "Mint")
        .withArgs(user1.address, amount, await capy.DAO_MINTER_ROLE());

      expect(await capy.balanceOf(user1.address)).to.equal(amount);

      const allocation = await capy.getMintAllocation();
      expect(allocation.daoMinted).to.equal(amount);
    });
  });

  describe("5. Revenue-Based Minting", function () {
    it("Should calculate correct mint amount (revenue / market value)", async function () {
      const { capy, admin, treasury } = await loadFixture(deployTokenFixture);

      const revenue = ethers.parseEther("1000");
      const marketValue = ethers.parseEther("10");
      const expectedTokens = ethers.parseEther("100"); // 1000 / 10 = 100 tokens

      await expect(
        capy.connect(admin).revenueMint(treasury.address, revenue, marketValue)
      )
        .to.emit(capy, "RevenueMint")
        .withArgs(revenue, marketValue, expectedTokens);

      expect(await capy.balanceOf(treasury.address)).to.equal(expectedTokens);
    });

    it("Should require revenue > 0", async function () {
      const { capy, admin, treasury } = await loadFixture(deployTokenFixture);

      const revenue = 0;
      const marketValue = ethers.parseEther("10");

      await expect(
        capy.connect(admin).revenueMint(treasury.address, revenue, marketValue)
      ).to.be.revertedWithCustomError(capy, "InvalidRevenue");
    });

    it("Should require market value > 0", async function () {
      const { capy, admin, treasury } = await loadFixture(deployTokenFixture);

      const revenue = ethers.parseEther("1000");
      const marketValue = 0;

      await expect(
        capy.connect(admin).revenueMint(treasury.address, revenue, marketValue)
      ).to.be.revertedWithCustomError(capy, "InvalidMarketValue");
    });
  });

  describe("6. Transfer Hooks", function () {
    it("Should apply 1% burn and 1% treasury fee on regular transfers", async function () {
      const { capy, admin, user1, user2, treasury } = await loadFixture(
        deployTokenFixture
      );

      const mintAmount = ethers.parseUnits("10000", 18);
      await capy.connect(admin).teamMint(user1.address, mintAmount);

      const transferAmount = ethers.parseUnits("1000", 18);
      const burnAmount = (transferAmount * 1n) / 100n; // 1%
      const treasuryFee = (transferAmount * 1n) / 100n; // 1%
      const recipientAmount = transferAmount - burnAmount - treasuryFee; // 98%

      const initialSupply = await capy.totalSupply();
      const initialTreasuryBalance = await capy.balanceOf(treasury.address);

      await expect(capy.connect(user1).transfer(user2.address, transferAmount))
        .to.emit(capy, "TreasuryFee")
        .withArgs(user1.address, treasury.address, treasuryFee);

      // Recipient receives 98%
      expect(await capy.balanceOf(user2.address)).to.equal(recipientAmount);

      // Treasury receives 1%
      expect(await capy.balanceOf(treasury.address)).to.equal(
        initialTreasuryBalance + treasuryFee
      );

      // Total supply reduced by 1% (burned)
      expect(await capy.totalSupply()).to.equal(initialSupply - burnAmount);
    });

    it("Should correctly reduce totalSupply from burn", async function () {
      const { capy, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      const mintAmount = ethers.parseUnits("10000", 18);
      await capy.connect(admin).teamMint(user1.address, mintAmount);

      const transferAmount = ethers.parseUnits("1000", 18);
      const burnAmount = (transferAmount * 1n) / 100n;

      const supplyBefore = await capy.totalSupply();
      await capy.connect(user1).transfer(user2.address, transferAmount);
      const supplyAfter = await capy.totalSupply();

      expect(supplyBefore - supplyAfter).to.equal(burnAmount);
    });

    it("Should update treasury balance correctly", async function () {
      const { capy, admin, user1, user2, treasury } = await loadFixture(
        deployTokenFixture
      );

      const mintAmount = ethers.parseUnits("10000", 18);
      await capy.connect(admin).teamMint(user1.address, mintAmount);

      const transferAmount = ethers.parseUnits("1000", 18);
      const treasuryFee = (transferAmount * 1n) / 100n;

      const treasuryBefore = await capy.balanceOf(treasury.address);
      await capy.connect(user1).transfer(user2.address, transferAmount);
      const treasuryAfter = await capy.balanceOf(treasury.address);

      expect(treasuryAfter - treasuryBefore).to.equal(treasuryFee);
    });
  });

  describe("7. Exemptions", function () {
    it("Should exempt treasury from fees", async function () {
      const { capy, admin, treasury, user1 } = await loadFixture(
        deployTokenFixture
      );

      // Mint to treasury
      const mintAmount = ethers.parseUnits("10000", 18);
      await capy.connect(admin).teamMint(treasury.address, mintAmount);

      const transferAmount = ethers.parseUnits("1000", 18);
      const supplyBefore = await capy.totalSupply();

      // Transfer from treasury (should be exempt)
      await capy.connect(treasury).transfer(user1.address, transferAmount);

      // User receives full amount (no fees)
      expect(await capy.balanceOf(user1.address)).to.equal(transferAmount);

      // Total supply unchanged (no burn)
      expect(await capy.totalSupply()).to.equal(supplyBefore);
    });

    it("Should exempt DAO from fees", async function () {
      const { capy, admin, dao, user1 } = await loadFixture(deployTokenFixture);

      // Mint to DAO
      const mintAmount = ethers.parseUnits("10000", 18);
      await capy.connect(admin).teamMint(dao.address, mintAmount);

      const transferAmount = ethers.parseUnits("1000", 18);
      const supplyBefore = await capy.totalSupply();

      // Transfer from DAO (should be exempt)
      await capy.connect(dao).transfer(user1.address, transferAmount);

      // User receives full amount (no fees)
      expect(await capy.balanceOf(user1.address)).to.equal(transferAmount);

      // Total supply unchanged (no burn)
      expect(await capy.totalSupply()).to.equal(supplyBefore);
    });

    it("Should bypass burn and fee logic for exempt transfers", async function () {
      const { capy, admin, treasury, dao } = await loadFixture(
        deployTokenFixture
      );

      const mintAmount = ethers.parseUnits("10000", 18);
      await capy.connect(admin).teamMint(treasury.address, mintAmount);

      const transferAmount = ethers.parseUnits("1000", 18);

      // Transfer from treasury to DAO (both exempt)
      await capy.connect(treasury).transfer(dao.address, transferAmount);

      // DAO receives exact amount
      expect(await capy.balanceOf(dao.address)).to.equal(transferAmount);
      expect(await capy.balanceOf(treasury.address)).to.equal(
        mintAmount - transferAmount
      );
    });

    it("Should allow admin to set and remove exemptions", async function () {
      const { capy, admin, user1 } = await loadFixture(deployTokenFixture);

      // Set exemption
      await expect(capy.connect(admin).setExemption(user1.address, true))
        .to.emit(capy, "ExemptionUpdated")
        .withArgs(user1.address, true);

      expect(await capy.isExempt(user1.address)).to.equal(true);

      // Remove exemption
      await expect(capy.connect(admin).setExemption(user1.address, false))
        .to.emit(capy, "ExemptionUpdated")
        .withArgs(user1.address, false);

      expect(await capy.isExempt(user1.address)).to.equal(false);
    });
  });

  describe("8. Pause & Emergency Stop", function () {
    it("Should allow admin to pause and unpause", async function () {
      const { capy, admin } = await loadFixture(deployTokenFixture);

      await expect(capy.connect(admin).pause())
        .to.emit(capy, "Paused")
        .withArgs(admin.address);

      expect(await capy.paused()).to.equal(true);

      await expect(capy.connect(admin).unpause())
        .to.emit(capy, "Unpaused")
        .withArgs(admin.address);

      expect(await capy.paused()).to.equal(false);
    });

    it("Should block transfers when paused", async function () {
      const { capy, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      const amount = ethers.parseUnits("1000", 18);
      await capy.connect(admin).teamMint(user1.address, amount);

      await capy.connect(admin).pause();

      await expect(
        capy.connect(user1).transfer(user2.address, amount)
      ).to.be.revertedWith("Pausable: paused");
    });

    it("Should block minting when paused", async function () {
      const { capy, admin, user1 } = await loadFixture(deployTokenFixture);

      await capy.connect(admin).pause();

      const amount = ethers.parseUnits("1000", 18);

      await expect(
        capy.connect(admin).teamMint(user1.address, amount)
      ).to.be.revertedWith("Pausable: paused");
    });
  });

  describe("9. Burn Logic", function () {
    it("Should allow user to burn own tokens", async function () {
      const { capy, admin, user1 } = await loadFixture(deployTokenFixture);

      const mintAmount = ethers.parseUnits("10000", 18);
      await capy.connect(admin).teamMint(user1.address, mintAmount);

      const burnAmount = ethers.parseUnits("1000", 18);

      await expect(capy.connect(user1).burn(burnAmount))
        .to.emit(capy, "Burn")
        .withArgs(user1.address, burnAmount)
        .to.emit(capy, "Transfer")
        .withArgs(user1.address, ethers.ZeroAddress, burnAmount);

      expect(await capy.balanceOf(user1.address)).to.equal(
        mintAmount - burnAmount
      );
    });

    it("Should respect allowance in burnFrom", async function () {
      const { capy, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      const mintAmount = ethers.parseUnits("10000", 18);
      await capy.connect(admin).teamMint(user1.address, mintAmount);

      const burnAmount = ethers.parseUnits("1000", 18);

      // Approve user2 to burn
      await capy.connect(user1).approve(user2.address, burnAmount);

      await expect(capy.connect(user2).burnFrom(user1.address, burnAmount))
        .to.emit(capy, "Burn")
        .withArgs(user1.address, burnAmount)
        .to.emit(capy, "Transfer")
        .withArgs(user1.address, ethers.ZeroAddress, burnAmount);

      expect(await capy.balanceOf(user1.address)).to.equal(
        mintAmount - burnAmount
      );
    });

    it("Should reduce totalSupply when burning", async function () {
      const { capy, admin, user1 } = await loadFixture(deployTokenFixture);

      const mintAmount = ethers.parseUnits("10000", 18);
      await capy.connect(admin).teamMint(user1.address, mintAmount);

      const burnAmount = ethers.parseUnits("1000", 18);
      const supplyBefore = await capy.totalSupply();

      await capy.connect(user1).burn(burnAmount);

      expect(await capy.totalSupply()).to.equal(supplyBefore - burnAmount);
    });
  });

  describe("10. Admin Functions", function () {
    it("Should allow admin to update treasury address", async function () {
      const { capy, admin, user1, treasury } = await loadFixture(
        deployTokenFixture
      );

      await expect(capy.connect(admin).setTreasuryAddress(user1.address))
        .to.emit(capy, "TreasuryAddressUpdated")
        .withArgs(treasury.address, user1.address);

      expect(await capy.getTreasuryAddress()).to.equal(user1.address);
      expect(await capy.isExempt(user1.address)).to.equal(true);
      expect(await capy.isExempt(treasury.address)).to.equal(false);
    });

    it("Should allow admin to update DAO address", async function () {
      const { capy, admin, user1, dao } = await loadFixture(deployTokenFixture);

      await expect(capy.connect(admin).setDaoAddress(user1.address))
        .to.emit(capy, "DaoAddressUpdated")
        .withArgs(dao.address, user1.address);

      expect(await capy.getDaoAddress()).to.equal(user1.address);
      expect(await capy.isExempt(user1.address)).to.equal(true);
      expect(await capy.isExempt(dao.address)).to.equal(false);
    });

    it("Should prevent setting zero address as treasury", async function () {
      const { capy, admin } = await loadFixture(deployTokenFixture);

      await expect(
        capy.connect(admin).setTreasuryAddress(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(capy, "ZeroAddress");
    });

    it("Should prevent setting zero address as DAO", async function () {
      const { capy, admin } = await loadFixture(deployTokenFixture);

      await expect(
        capy.connect(admin).setDaoAddress(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(capy, "ZeroAddress");
    });
  });

  describe("11. Ownership Security", function () {
    it("Should prevent transferring ownership to an EOA", async function () {
      const { capy, admin, user1, adminSigner } = await loadFixture(
        deployTokenFixture
      );

      // Try to transfer ownership to an EOA (should revert)
      const data = capy.interface.encodeFunctionData("transferOwnership", [
        user1.address,
      ]);
      const MockMultisig = await ethers.getContractFactory("MockMultisig");
      const multisig = MockMultisig.attach(admin.address);

      await expect(
        multisig.connect(adminSigner).execute(capy.target, data)
      ).to.be.revertedWithCustomError(capy, "AdminMustBeContract");
    });

    it("Should allow transferring ownership to another multisig", async function () {
      const { capy, admin, adminSigner } = await loadFixture(
        deployTokenFixture
      );

      // Deploy a new multisig
      const MockMultisig = await ethers.getContractFactory("MockMultisig");
      const newMultisig = await MockMultisig.deploy(adminSigner.address);

      // Transfer ownership to the new multisig
      const data = capy.interface.encodeFunctionData("transferOwnership", [
        newMultisig.target,
      ]);
      const currentMultisig = MockMultisig.attach(admin.address);

      await currentMultisig.connect(adminSigner).execute(capy.target, data);

      // Verify ownership changed
      expect(await capy.owner()).to.equal(newMultisig.target);
      expect(await capy.isOwnerMultisig()).to.equal(true);
    });

    it("Should prevent completing ownership handover to an EOA", async function () {
      const { capy, admin, user1, adminSigner } = await loadFixture(
        deployTokenFixture
      );

      // User1 requests ownership handover
      await capy.connect(user1).requestOwnershipHandover();

      // Admin tries to complete handover (should revert because user1 is EOA)
      const data = capy.interface.encodeFunctionData(
        "completeOwnershipHandover",
        [user1.address]
      );
      const MockMultisig = await ethers.getContractFactory("MockMultisig");
      const multisig = MockMultisig.attach(admin.address);

      await expect(
        multisig.connect(adminSigner).execute(capy.target, data)
      ).to.be.revertedWithCustomError(capy, "AdminMustBeContract");
    });

    it("Should prevent renouncing ownership", async function () {
      const { capy, admin, adminSigner } = await loadFixture(
        deployTokenFixture
      );

      const data = capy.interface.encodeFunctionData("renounceOwnership", []);
      const MockMultisig = await ethers.getContractFactory("MockMultisig");
      const multisig = MockMultisig.attach(admin.address);

      await expect(
        multisig.connect(adminSigner).execute(capy.target, data)
      ).to.be.revertedWith("Ownership cannot be renounced");
    });
  });

  describe("12. Event Logging", function () {
    it("Should emit Mint events", async function () {
      const { capy, admin, user1, TEAM_MINTER_ROLE } = await loadFixture(
        deployTokenFixture
      );

      const amount = ethers.parseUnits("1000", 18);

      await expect(capy.connect(admin).teamMint(user1.address, amount))
        .to.emit(capy, "Mint")
        .withArgs(user1.address, amount, TEAM_MINTER_ROLE);
    });

    it("Should emit RevenueMint events", async function () {
      const { capy, admin, treasury } = await loadFixture(deployTokenFixture);

      const revenue = ethers.parseEther("1000");
      const marketValue = ethers.parseEther("10");
      const expectedTokens = ethers.parseEther("100"); // 1000 / 10 = 100 tokens

      await expect(
        capy.connect(admin).revenueMint(treasury.address, revenue, marketValue)
      )
        .to.emit(capy, "RevenueMint")
        .withArgs(revenue, marketValue, expectedTokens);
    });

    it("Should emit RoleGranted/RoleRevoked events", async function () {
      const { capy, admin, user1, TEAM_MINTER_ROLE } = await loadFixture(
        deployTokenFixture
      );

      await expect(
        capy.connect(admin).grantRoles(user1.address, TEAM_MINTER_ROLE)
      )
        .to.emit(capy, "RoleGranted")
        .withArgs(TEAM_MINTER_ROLE, user1.address, admin.address);

      await expect(
        capy.connect(admin).revokeRoles(user1.address, TEAM_MINTER_ROLE)
      )
        .to.emit(capy, "RoleRevoked")
        .withArgs(TEAM_MINTER_ROLE, user1.address, admin.address);
    });
  });
});
