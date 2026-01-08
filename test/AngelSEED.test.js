const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("AngelSEED Token", function () {
  async function deployTokenFixture() {
    const [adminSigner, rewardMinter, user1, user2, user3] =
      await ethers.getSigners();

    // Deploy MockMultisig to act as admin (satisfies contract requirement)
    const MockMultisig = await ethers.getContractFactory("MockMultisig");
    const multisig = await MockMultisig.deploy(adminSigner.address);

    const AngelSEED = await ethers.getContractFactory("AngelSEED");
    const seed = await AngelSEED.deploy(multisig.target);

    // Get role identifiers
    const DEFAULT_ADMIN_ROLE = await seed.DEFAULT_ADMIN_ROLE();
    const REWARD_MINTER_ROLE = await seed.REWARD_MINTER_ROLE();

    // Helper function to execute SEED functions through the multisig
    const executeAsAdmin = async (functionName, ...args) => {
      const data = seed.interface.encodeFunctionData(functionName, args);
      return multisig.connect(adminSigner).execute(seed.target, data);
    };

    // Create wrapper for seed.connect(admin) pattern
    // When tests call seed.connect(admin).function(), it will execute through multisig
    const originalConnect = seed.connect.bind(seed);
    seed.connect = (signer) => {
      // If connecting as admin (multisig), return wrapped contract
      if (signer && signer.address === multisig.target) {
        return {
          rewardMint: (to, amount, reason) =>
            executeAsAdmin("rewardMint", to, amount, reason),
          batchRewardMint: (recipients, amounts, reason) =>
            executeAsAdmin("batchRewardMint", recipients, amounts, reason),
          grantRoles: (user, roles) =>
            executeAsAdmin("grantRoles", user, roles),
          revokeRoles: (user, roles) =>
            executeAsAdmin("revokeRoles", user, roles),
          pause: () => executeAsAdmin("pause"),
          unpause: () => executeAsAdmin("unpause"),
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
      seed,
      admin,
      adminSigner,
      executeAsAdmin,
      rewardMinter,
      user1,
      user2,
      user3,
      DEFAULT_ADMIN_ROLE,
      REWARD_MINTER_ROLE,
    };
  }

  describe("1. Deployment & Initial State", function () {
    it("Should have correct name, symbol, and decimals", async function () {
      const { seed } = await loadFixture(deployTokenFixture);

      expect(await seed.name()).to.equal("AngelSEED");
      expect(await seed.symbol()).to.equal("ANGEL");
      expect(await seed.decimals()).to.equal(18);
    });

    it("Should start with totalSupply = 0", async function () {
      const { seed } = await loadFixture(deployTokenFixture);

      expect(await seed.totalSupply()).to.equal(0);
    });

    it("Should have MAX_SUPPLY enforced", async function () {
      const { seed } = await loadFixture(deployTokenFixture);

      const maxSupply = await seed.getMaxSupply();
      expect(maxSupply).to.equal(ethers.parseUnits("10000000000", 18)); // 10 billion
    });

    it("Should start unpaused", async function () {
      const { seed } = await loadFixture(deployTokenFixture);

      expect(await seed.paused()).to.equal(false);
    });

    it("Should enforce admin is a contract (multisig)", async function () {
      const { seed } = await loadFixture(deployTokenFixture);

      // Verify the owner is a contract (multisig)
      expect(await seed.isOwnerMultisig()).to.equal(true);
    });

    it("Should revert if admin is an EOA during deployment", async function () {
      const [eoaAdmin] = await ethers.getSigners();

      const AngelSEED = await ethers.getContractFactory("AngelSEED");

      // Should revert because eoaAdmin is not a contract
      await expect(
        AngelSEED.deploy(eoaAdmin.address)
      ).to.be.revertedWithCustomError(AngelSEED, "AdminMustBeContract");
    });
  });

  describe("2. Access Control", function () {
    it("Should assign DEFAULT_ADMIN_ROLE to admin (multisig)", async function () {
      const { seed, admin, DEFAULT_ADMIN_ROLE } = await loadFixture(
        deployTokenFixture
      );

      expect(await seed.owner()).to.equal(admin.address);
    });

    it("Should assign REWARD_MINTER_ROLE to admin", async function () {
      const { seed, admin, REWARD_MINTER_ROLE } = await loadFixture(
        deployTokenFixture
      );

      expect(await seed.hasRole(REWARD_MINTER_ROLE, admin.address)).to.equal(
        true
      );
    });

    it("Should prevent unauthorized users from minting", async function () {
      const { seed, user1 } = await loadFixture(deployTokenFixture);

      const amount = ethers.parseUnits("1000", 18);

      await expect(
        seed.connect(user1).rewardMint(user1.address, amount, "Test reward")
      ).to.be.revertedWithCustomError(seed, "Unauthorized");
    });

    it("Should allow admin to grant and revoke roles", async function () {
      const { seed, admin, user1, REWARD_MINTER_ROLE, executeAsAdmin } =
        await loadFixture(deployTokenFixture);

      await executeAsAdmin("grantRoles", user1.address, REWARD_MINTER_ROLE);
      expect(await seed.hasRole(REWARD_MINTER_ROLE, user1.address)).to.equal(
        true
      );

      await executeAsAdmin("revokeRoles", user1.address, REWARD_MINTER_ROLE);
      expect(await seed.hasRole(REWARD_MINTER_ROLE, user1.address)).to.equal(
        false
      );
    });
  });

  describe("3. Hard Cap Enforcement", function () {
    it("Should allow minting up to cap", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      const maxSupply = await seed.getMaxSupply();
      await seed
        .connect(admin)
        .rewardMint(user1.address, maxSupply, "Max supply test");

      expect(await seed.totalSupply()).to.equal(maxSupply);
      expect(await seed.getTotalMinted()).to.equal(maxSupply);
    });

    it("Should revert when minting above cap", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      const maxSupply = await seed.getMaxSupply();
      const overAmount = maxSupply + 1n;

      await expect(
        seed
          .connect(admin)
          .rewardMint(user1.address, overAmount, "Over cap test")
      ).to.be.revertedWithCustomError(seed, "MaxSupplyExceeded");
    });

    it("Should confirm burn does not free mint capacity", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      const maxSupply = await seed.getMaxSupply();

      // Mint to cap
      await seed
        .connect(admin)
        .rewardMint(user1.address, maxSupply, "Mint to cap");

      // User burns 1000 tokens
      const burnAmount = ethers.parseUnits("1000", 18);
      await seed.connect(user1).burn(burnAmount);

      // Try to mint 1 more token (should fail because totalMinted = cap)
      await expect(
        seed.connect(admin).rewardMint(user1.address, 1n, "Try after burn")
      ).to.be.revertedWithCustomError(seed, "MaxSupplyExceeded");

      // Verify totalMinted hasn't changed despite burn
      expect(await seed.getTotalMinted()).to.equal(maxSupply);
    });
  });

  describe("4. Reward Minting", function () {
    it("Should allow reward mint within cap", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      const amount = ethers.parseUnits("1000", 18);
      await seed
        .connect(admin)
        .rewardMint(user1.address, amount, "Community reward");

      expect(await seed.balanceOf(user1.address)).to.equal(amount);
      expect(await seed.totalSupply()).to.equal(amount);
    });

    it("Should allow granted reward minter to mint", async function () {
      const {
        seed,
        admin,
        rewardMinter,
        user1,
        REWARD_MINTER_ROLE,
        executeAsAdmin,
      } = await loadFixture(deployTokenFixture);

      // Grant reward minter role
      await executeAsAdmin(
        "grantRoles",
        rewardMinter.address,
        REWARD_MINTER_ROLE
      );

      const amount = ethers.parseUnits("1000", 18);
      await seed
        .connect(rewardMinter)
        .rewardMint(user1.address, amount, "Granted minter reward");

      expect(await seed.balanceOf(user1.address)).to.equal(amount);
    });

    it("Should revert when minting to zero address", async function () {
      const { seed, admin } = await loadFixture(deployTokenFixture);

      const amount = ethers.parseUnits("1000", 18);

      await expect(
        seed.connect(admin).rewardMint(ethers.ZeroAddress, amount, "Test")
      ).to.be.revertedWithCustomError(seed, "ZeroAddress");
    });

    it("Should revert when minting zero amount", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      await expect(
        seed.connect(admin).rewardMint(user1.address, 0, "Test")
      ).to.be.revertedWithCustomError(seed, "InvalidAmount");
    });

    it("Should revert when reason is empty", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      const amount = ethers.parseUnits("1000", 18);

      await expect(
        seed.connect(admin).rewardMint(user1.address, amount, "")
      ).to.be.revertedWithCustomError(seed, "InvalidReason");
    });

    it("Should revert when reason exceeds max length", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      const amount = ethers.parseUnits("1000", 18);
      const longReason = "a".repeat(257); // MAX_REASON_LENGTH is 256

      await expect(
        seed.connect(admin).rewardMint(user1.address, amount, longReason)
      ).to.be.revertedWithCustomError(seed, "InvalidReason");
    });
  });

  describe("4b. Batch Reward Minting", function () {
    it("Should allow batch minting to multiple recipients", async function () {
      const { seed, admin, user1, user2, user3 } = await loadFixture(
        deployTokenFixture
      );

      const recipients = [user1.address, user2.address, user3.address];
      const amounts = [
        ethers.parseUnits("1000", 18),
        ethers.parseUnits("2000", 18),
        ethers.parseUnits("3000", 18),
      ];
      const reason = "Batch community rewards";

      await seed.connect(admin).batchRewardMint(recipients, amounts, reason);

      expect(await seed.balanceOf(user1.address)).to.equal(amounts[0]);
      expect(await seed.balanceOf(user2.address)).to.equal(amounts[1]);
      expect(await seed.balanceOf(user3.address)).to.equal(amounts[2]);

      const totalAmount = amounts[0] + amounts[1] + amounts[2];
      expect(await seed.totalSupply()).to.equal(totalAmount);
      expect(await seed.getTotalMinted()).to.equal(totalAmount);
    });

    it("Should emit RewardMint events for each recipient", async function () {
      const { seed, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      const recipients = [user1.address, user2.address];
      const amounts = [
        ethers.parseUnits("1000", 18),
        ethers.parseUnits("2000", 18),
      ];
      const reason = "Batch rewards";

      const tx = await seed
        .connect(admin)
        .batchRewardMint(recipients, amounts, reason);

      await expect(tx)
        .to.emit(seed, "RewardMint")
        .withArgs(user1.address, amounts[0], reason);

      await expect(tx)
        .to.emit(seed, "RewardMint")
        .withArgs(user2.address, amounts[1], reason);
    });

    it("Should allow granted reward minter to batch mint", async function () {
      const {
        seed,
        rewardMinter,
        user1,
        user2,
        REWARD_MINTER_ROLE,
        executeAsAdmin,
      } = await loadFixture(deployTokenFixture);

      // Grant reward minter role
      await executeAsAdmin(
        "grantRoles",
        rewardMinter.address,
        REWARD_MINTER_ROLE
      );

      const recipients = [user1.address, user2.address];
      const amounts = [
        ethers.parseUnits("500", 18),
        ethers.parseUnits("750", 18),
      ];
      const reason = "Granted minter batch";

      await seed
        .connect(rewardMinter)
        .batchRewardMint(recipients, amounts, reason);

      expect(await seed.balanceOf(user1.address)).to.equal(amounts[0]);
      expect(await seed.balanceOf(user2.address)).to.equal(amounts[1]);
    });

    it("Should revert when arrays have different lengths", async function () {
      const { seed, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      const recipients = [user1.address, user2.address];
      const amounts = [ethers.parseUnits("1000", 18)]; // Only 1 amount for 2 recipients
      const reason = "Test";

      await expect(
        seed.connect(admin).batchRewardMint(recipients, amounts, reason)
      ).to.be.revertedWithCustomError(seed, "ArrayLengthMismatch");
    });

    it("Should revert when arrays are empty", async function () {
      const { seed, admin } = await loadFixture(deployTokenFixture);

      const recipients = [];
      const amounts = [];
      const reason = "Test";

      await expect(
        seed.connect(admin).batchRewardMint(recipients, amounts, reason)
      ).to.be.revertedWithCustomError(seed, "EmptyArrays");
    });

    it("Should revert when any recipient is zero address", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      const recipients = [user1.address, ethers.ZeroAddress];
      const amounts = [
        ethers.parseUnits("1000", 18),
        ethers.parseUnits("1000", 18),
      ];
      const reason = "Test";

      await expect(
        seed.connect(admin).batchRewardMint(recipients, amounts, reason)
      ).to.be.revertedWithCustomError(seed, "ZeroAddress");
    });

    it("Should revert when any amount is zero", async function () {
      const { seed, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      const recipients = [user1.address, user2.address];
      const amounts = [ethers.parseUnits("1000", 18), 0];
      const reason = "Test";

      await expect(
        seed.connect(admin).batchRewardMint(recipients, amounts, reason)
      ).to.be.revertedWithCustomError(seed, "InvalidAmount");
    });

    it("Should revert when batch minting would exceed max supply", async function () {
      const { seed, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      const maxSupply = await seed.getMaxSupply();
      const recipients = [user1.address, user2.address];
      const amounts = [maxSupply / 2n + 1n, maxSupply / 2n + 1n]; // Together exceed max
      const reason = "Test";

      await expect(
        seed.connect(admin).batchRewardMint(recipients, amounts, reason)
      ).to.be.revertedWithCustomError(seed, "MaxSupplyExceeded");
    });

    it("Should revert when reason is empty for batch mint", async function () {
      const { seed, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      const recipients = [user1.address, user2.address];
      const amounts = [
        ethers.parseUnits("1000", 18),
        ethers.parseUnits("1000", 18),
      ];
      const reason = "";

      await expect(
        seed.connect(admin).batchRewardMint(recipients, amounts, reason)
      ).to.be.revertedWithCustomError(seed, "InvalidReason");
    });

    it("Should revert when reason exceeds max length for batch mint", async function () {
      const { seed, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      const recipients = [user1.address, user2.address];
      const amounts = [
        ethers.parseUnits("1000", 18),
        ethers.parseUnits("1000", 18),
      ];
      const longReason = "a".repeat(257); // MAX_REASON_LENGTH is 256

      await expect(
        seed.connect(admin).batchRewardMint(recipients, amounts, longReason)
      ).to.be.revertedWithCustomError(seed, "InvalidReason");
    });

    it("Should revert when unauthorized user tries to batch mint", async function () {
      const { seed, user1, user2, user3 } = await loadFixture(
        deployTokenFixture
      );

      const recipients = [user2.address, user3.address];
      const amounts = [
        ethers.parseUnits("1000", 18),
        ethers.parseUnits("1000", 18),
      ];
      const reason = "Test";

      await expect(
        seed.connect(user1).batchRewardMint(recipients, amounts, reason)
      ).to.be.revertedWithCustomError(seed, "Unauthorized");
    });

    it("Should block batch minting when paused", async function () {
      const { seed, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      await seed.connect(admin).pause();

      const recipients = [user1.address, user2.address];
      const amounts = [
        ethers.parseUnits("1000", 18),
        ethers.parseUnits("1000", 18),
      ];
      const reason = "Test";

      await expect(
        seed.connect(admin).batchRewardMint(recipients, amounts, reason)
      ).to.be.revertedWith("Pausable: paused");
    });

    it("Should handle large batch minting correctly", async function () {
      const { seed, admin, user1, user2, user3 } = await loadFixture(
        deployTokenFixture
      );

      // Create arrays with 10 recipients (reusing addresses)
      const recipients = Array(10).fill(user1.address);
      recipients[5] = user2.address;
      recipients[9] = user3.address;

      const amountPerRecipient = ethers.parseUnits("100", 18);
      const amounts = Array(10).fill(amountPerRecipient);
      const reason = "Large batch distribution";

      await seed.connect(admin).batchRewardMint(recipients, amounts, reason);

      // user1 receives 8 times (indices 0-4, 6-8)
      // user2 receives 1 time (index 5)
      // user3 receives 1 time (index 9)
      expect(await seed.balanceOf(user1.address)).to.equal(
        amountPerRecipient * 8n
      );
      expect(await seed.balanceOf(user2.address)).to.equal(amountPerRecipient);
      expect(await seed.balanceOf(user3.address)).to.equal(amountPerRecipient);

      const totalAmount = amountPerRecipient * 10n;
      expect(await seed.totalSupply()).to.equal(totalAmount);
    });
  });

  describe("5. Pause & Emergency Stop", function () {
    it("Should allow admin to pause and unpause", async function () {
      const { seed, admin } = await loadFixture(deployTokenFixture);

      await seed.connect(admin).pause();
      expect(await seed.paused()).to.equal(true);

      await seed.connect(admin).unpause();
      expect(await seed.paused()).to.equal(false);
    });

    it("Should block transfers when paused", async function () {
      const { seed, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      const amount = ethers.parseUnits("1000", 18);
      await seed.connect(admin).rewardMint(user1.address, amount, "Test mint");

      await seed.connect(admin).pause();

      await expect(
        seed.connect(user1).transfer(user2.address, amount)
      ).to.be.revertedWith("Pausable: paused");
    });

    it("Should block minting when paused", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      await seed.connect(admin).pause();

      const amount = ethers.parseUnits("1000", 18);
      await expect(
        seed.connect(admin).rewardMint(user1.address, amount, "Test")
      ).to.be.revertedWith("Pausable: paused");
    });
  });

  describe("6. Burn Logic", function () {
    it("Should allow user to burn own tokens", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      const mintAmount = ethers.parseUnits("1000", 18);
      await seed
        .connect(admin)
        .rewardMint(user1.address, mintAmount, "Test mint");

      const burnAmount = ethers.parseUnits("100", 18);

      await expect(seed.connect(user1).burn(burnAmount))
        .to.emit(seed, "Burn")
        .withArgs(user1.address, burnAmount)
        .to.emit(seed, "Transfer")
        .withArgs(user1.address, ethers.ZeroAddress, burnAmount);

      expect(await seed.balanceOf(user1.address)).to.equal(
        mintAmount - burnAmount
      );
      expect(await seed.totalSupply()).to.equal(mintAmount - burnAmount);
    });

    it("Should respect allowance in burnFrom", async function () {
      const { seed, admin, user1, user2 } = await loadFixture(
        deployTokenFixture
      );

      const mintAmount = ethers.parseUnits("1000", 18);
      await seed
        .connect(admin)
        .rewardMint(user1.address, mintAmount, "Test mint");

      const burnAmount = ethers.parseUnits("100", 18);
      await seed.connect(user1).approve(user2.address, burnAmount);

      await expect(seed.connect(user2).burnFrom(user1.address, burnAmount))
        .to.emit(seed, "Burn")
        .withArgs(user1.address, burnAmount)
        .to.emit(seed, "Transfer")
        .withArgs(user1.address, ethers.ZeroAddress, burnAmount);

      expect(await seed.balanceOf(user1.address)).to.equal(
        mintAmount - burnAmount
      );
    });

    it("Should reduce totalSupply when burning", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      const mintAmount = ethers.parseUnits("1000", 18);
      await seed
        .connect(admin)
        .rewardMint(user1.address, mintAmount, "Test mint");

      const burnAmount = ethers.parseUnits("500", 18);
      await seed.connect(user1).burn(burnAmount);

      expect(await seed.totalSupply()).to.equal(mintAmount - burnAmount);
    });

    it("Should not reduce totalMinted when burning", async function () {
      const { seed, admin, user1 } = await loadFixture(deployTokenFixture);

      const mintAmount = ethers.parseUnits("1000", 18);
      await seed
        .connect(admin)
        .rewardMint(user1.address, mintAmount, "Test mint");

      const burnAmount = ethers.parseUnits("500", 18);
      await seed.connect(user1).burn(burnAmount);

      expect(await seed.getTotalMinted()).to.equal(mintAmount);
    });
  });

  describe("7. Ownership Security", function () {
    it("Should prevent transferring ownership to an EOA", async function () {
      const { seed, admin, user1, adminSigner } = await loadFixture(
        deployTokenFixture
      );

      // Try to transfer ownership to an EOA (should revert)
      const data = seed.interface.encodeFunctionData("transferOwnership", [
        user1.address,
      ]);
      const MockMultisig = await ethers.getContractFactory("MockMultisig");
      const multisig = MockMultisig.attach(admin.address);

      await expect(
        multisig.connect(adminSigner).execute(seed.target, data)
      ).to.be.revertedWithCustomError(seed, "AdminMustBeContract");
    });

    it("Should allow transferring ownership to another multisig", async function () {
      const { seed, admin, adminSigner } = await loadFixture(
        deployTokenFixture
      );

      // Deploy a new multisig
      const MockMultisig = await ethers.getContractFactory("MockMultisig");
      const newMultisig = await MockMultisig.deploy(adminSigner.address);

      // Transfer ownership to the new multisig
      const data = seed.interface.encodeFunctionData("transferOwnership", [
        newMultisig.target,
      ]);
      const currentMultisig = MockMultisig.attach(admin.address);

      await currentMultisig.connect(adminSigner).execute(seed.target, data);

      // Verify ownership changed
      expect(await seed.owner()).to.equal(newMultisig.target);
      expect(await seed.isOwnerMultisig()).to.equal(true);
    });

    it("Should prevent completing ownership handover to an EOA", async function () {
      const { seed, admin, user1, adminSigner } = await loadFixture(
        deployTokenFixture
      );

      // User1 requests ownership handover
      await seed.connect(user1).requestOwnershipHandover();

      // Admin tries to complete handover (should revert because user1 is EOA)
      const data = seed.interface.encodeFunctionData(
        "completeOwnershipHandover",
        [user1.address]
      );
      const MockMultisig = await ethers.getContractFactory("MockMultisig");
      const multisig = MockMultisig.attach(admin.address);

      await expect(
        multisig.connect(adminSigner).execute(seed.target, data)
      ).to.be.revertedWithCustomError(seed, "AdminMustBeContract");
    });

    it("Should prevent renouncing ownership", async function () {
      const { seed, admin, adminSigner } = await loadFixture(
        deployTokenFixture
      );

      const data = seed.interface.encodeFunctionData("renounceOwnership", []);
      const MockMultisig = await ethers.getContractFactory("MockMultisig");
      const multisig = MockMultisig.attach(admin.address);

      await expect(
        multisig.connect(adminSigner).execute(seed.target, data)
      ).to.be.revertedWith("Ownership cannot be renounced");
    });
  });

  describe("8. Event Logging", function () {
    it("Should emit RewardMint events", async function () {
      const { seed, admin, user1, REWARD_MINTER_ROLE } = await loadFixture(
        deployTokenFixture
      );

      const amount = ethers.parseUnits("1000", 18);
      const reason = "Test reward";

      await expect(
        seed.connect(admin).rewardMint(user1.address, amount, reason)
      )
        .to.emit(seed, "RewardMint")
        .withArgs(user1.address, amount, reason);
    });

    it("Should emit RoleGranted/RoleRevoked events", async function () {
      const { seed, admin, user1, REWARD_MINTER_ROLE } = await loadFixture(
        deployTokenFixture
      );

      await expect(
        seed.connect(admin).grantRoles(user1.address, REWARD_MINTER_ROLE)
      )
        .to.emit(seed, "RoleGranted")
        .withArgs(REWARD_MINTER_ROLE, user1.address, admin.address);

      await expect(
        seed.connect(admin).revokeRoles(user1.address, REWARD_MINTER_ROLE)
      )
        .to.emit(seed, "RoleRevoked")
        .withArgs(REWARD_MINTER_ROLE, user1.address, admin.address);
    });

    it("Should emit Paused/Unpaused events", async function () {
      const { seed, admin } = await loadFixture(deployTokenFixture);

      await expect(seed.connect(admin).pause())
        .to.emit(seed, "Paused")
        .withArgs(admin.address);

      await expect(seed.connect(admin).unpause())
        .to.emit(seed, "Unpaused")
        .withArgs(admin.address);
    });
  });
});
