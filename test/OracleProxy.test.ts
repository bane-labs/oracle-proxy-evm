import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import {
  OracleProxy,
  MockNativeBridge,
  MockMessageBridge,
  NeoSerializerHelper,
} from "../typechain-types";

describe("OracleProxy", () => {
  let owner: HardhatEthersSigner;
  let other: HardhatEthersSigner;
  let mockBridge: MockNativeBridge;
  let mockMessageBridge: MockMessageBridge;
  let serializerHelper: NeoSerializerHelper;
  let proxy: OracleProxy;

  const INITIAL_NONCE = 5n;

  beforeEach(async () => {
    [owner, other] = await ethers.getSigners();

    // Deploy mocks
    const MockNativeBridgeFactory = await ethers.getContractFactory("MockNativeBridge");
    mockBridge = (await MockNativeBridgeFactory.deploy(INITIAL_NONCE)) as unknown as MockNativeBridge;

    const MockMessageBridgeFactory = await ethers.getContractFactory("MockMessageBridge");
    mockMessageBridge = (await MockMessageBridgeFactory.deploy()) as unknown as MockMessageBridge;

    const NeoSerializerHelperFactory = await ethers.getContractFactory("NeoSerializerHelper");
    serializerHelper = (await NeoSerializerHelperFactory.deploy()) as unknown as NeoSerializerHelper;

    // Deploy OracleProxy via UUPS proxy
    const OracleProxyFactory = await ethers.getContractFactory("OracleProxy", owner);
    proxy = (await upgrades.deployProxy(
      OracleProxyFactory,
      [
        await mockBridge.getAddress(),
        await mockMessageBridge.getAddress(),
        other.address, // executionManager (just needs to be non-zero)
        owner.address,
      ],
      { kind: "uups", initializer: "initialize" }
    )) as unknown as OracleProxy;
  });

  // ── Initialization ──────────────────────────────────────────────────────────

  describe("Initialization", () => {
    it("sets the owner correctly", async () => {
      expect(await proxy.owner()).to.equal(owner.address);
    });

    it("sets the bridge address correctly", async () => {
      expect(await proxy.bridge()).to.equal(await mockBridge.getAddress());
    });

    it("sets the messageBridge address correctly", async () => {
      expect(await proxy.messageBridge()).to.equal(await mockMessageBridge.getAddress());
    });

    it("sets the executionManager address correctly", async () => {
      expect(await proxy.executionManager()).to.equal(other.address);
    });

    it("starts with requestIdCounter = 0", async () => {
      expect(await proxy.requestIdCounter()).to.equal(0n);
    });

    it("reverts if bridge address is zero", async () => {
      const OracleProxyFactory = await ethers.getContractFactory("OracleProxy", owner);
      await expect(
        upgrades.deployProxy(
          OracleProxyFactory,
          [ethers.ZeroAddress, await mockMessageBridge.getAddress(), other.address, owner.address],
          { kind: "uups", initializer: "initialize" }
        )
      ).to.be.revertedWith("Invalid bridge address");
    });

    it("reverts if messageBridge address is zero", async () => {
      const OracleProxyFactory = await ethers.getContractFactory("OracleProxy", owner);
      await expect(
        upgrades.deployProxy(
          OracleProxyFactory,
          [await mockBridge.getAddress(), ethers.ZeroAddress, other.address, owner.address],
          { kind: "uups", initializer: "initialize" }
        )
      ).to.be.revertedWith("Invalid message bridge address");
    });

    it("reverts if executionManager address is zero", async () => {
      const OracleProxyFactory = await ethers.getContractFactory("OracleProxy", owner);
      await expect(
        upgrades.deployProxy(
          OracleProxyFactory,
          [await mockBridge.getAddress(), await mockMessageBridge.getAddress(), ethers.ZeroAddress, owner.address],
          { kind: "uups", initializer: "initialize" }
        )
      ).to.be.revertedWith("Invalid execution manager address");
    });

    it("cannot be initialized a second time", async () => {
      await expect(
        proxy.initialize(
          await mockBridge.getAddress(),
          await mockMessageBridge.getAddress(),
          other.address,
          owner.address
        )
      ).to.be.revertedWithCustomError(proxy, "InvalidInitialization");
    });
  });

  // ── onOracleResult ──────────────────────────────────────────────────────────

  describe("onOracleResult", () => {
    it("stores the oracle result and marks it as received", async () => {
      const requestId = 42n;
      const result = ethers.toUtf8Bytes('{"USD":{"price":1.0}}');

      await proxy.connect(other).onOracleResult(requestId, result);

      expect(await proxy.hasResult(requestId)).to.be.true;
      const [storedResult, exists] = await proxy.getOracleResult(requestId);
      expect(exists).to.be.true;
      expect(storedResult).to.equal(ethers.hexlify(result));
    });

    it("emits OracleResultReceived event", async () => {
      const requestId = 7n;
      const result = ethers.toUtf8Bytes("test-result");

      await expect(proxy.connect(other).onOracleResult(requestId, result))
        .to.emit(proxy, "OracleResultReceived")
        .withArgs(requestId, ethers.hexlify(result));
    });

    it("returns false / empty bytes for a request that has no result", async () => {
      const [storedResult, exists] = await proxy.getOracleResult(999n);
      expect(exists).to.be.false;
      expect(storedResult).to.equal("0x");
    });

    it("hasOracleResult returns false before and true after storing", async () => {
      expect(await proxy.hasOracleResult(1n)).to.be.false;
      await proxy.onOracleResult(1n, ethers.toUtf8Bytes("data"));
      expect(await proxy.hasOracleResult(1n)).to.be.true;
    });

    it("can overwrite an existing result with a new one", async () => {
      const requestId = 1n;
      const first  = ethers.toUtf8Bytes("first");
      const second = ethers.toUtf8Bytes("second-longer");

      await proxy.onOracleResult(requestId, first);
      await proxy.onOracleResult(requestId, second);

      const [storedResult] = await proxy.getOracleResult(requestId);
      expect(storedResult).to.equal(ethers.hexlify(second));
    });
  });

  // ── initiateOracleCall ──────────────────────────────────────────────────────

  describe("initiateOracleCall", () => {
    // A dummy N3 oracle contract address (just needs to be non-zero for serialization)
    const ORACLE_CONTRACT = "0x0000000000000000000000000000000000001234";

    const gasAmount    = ethers.parseEther("0.1");
    const maxBridgeFee = ethers.parseEther("0.01");
    const maxMsgFee    = ethers.parseEther("0.005");
    const totalValue   = gasAmount + maxBridgeFee + maxMsgFee;

    async function buildCall(): Promise<string> {
      return serializerHelper.buildOracleCall(
        ORACLE_CONTRACT,
        "https://api.example.com/price",
        "$.USD.price",
        await proxy.getAddress(),   // callbackContract = this proxy
        "onOracleResult",
        10_000_000n                 // gasForResponse
      );
    }

    it("increments requestIdCounter on each call", async () => {
      const serializedOracleCall = await buildCall();
      expect(await proxy.requestIdCounter()).to.equal(0n);

      await proxy.initiateOracleCall(
        other.address, gasAmount, maxBridgeFee, serializedOracleCall, maxMsgFee, false,
        { value: totalValue }
      );
      expect(await proxy.requestIdCounter()).to.equal(1n);

      await proxy.initiateOracleCall(
        other.address, gasAmount, maxBridgeFee, serializedOracleCall, maxMsgFee, false,
        { value: totalValue }
      );
      expect(await proxy.requestIdCounter()).to.equal(2n);
    });

    it("emits OracleCallInitiated with correct requestId and withdrawalNonce", async () => {
      // INITIAL_NONCE = 5, so withdrawalNonce should be 6
      const expectedWithdrawalNonce = INITIAL_NONCE + 1n;
      const expectedRequestId = 0n;
      const serializedOracleCall = await buildCall();

      const tx = await proxy.initiateOracleCall(
        other.address, gasAmount, maxBridgeFee, serializedOracleCall, maxMsgFee, false,
        { value: totalValue }
      );

      await expect(tx)
        .to.emit(proxy, "OracleCallInitiated")
        .withArgs(
          expectedRequestId,
          expectedWithdrawalNonce,
          1n,           // first messageNonce from MockMessageBridge
          owner.address,
          (v: string) => v.startsWith("0x") // enrichedCall bytes — just verify it's bytes
        );
    });

    it("reverts when msg.value is insufficient", async () => {
      const serializedOracleCall = await buildCall();
      const insufficientValue = gasAmount + maxBridgeFee + maxMsgFee - 1n;
      await expect(
        proxy.initiateOracleCall(
          other.address, gasAmount, maxBridgeFee, serializedOracleCall, maxMsgFee, false,
          { value: insufficientValue }
        )
      ).to.be.revertedWith("Insufficient value");
    });

    it("returns the correct requestId and messageNonce", async () => {
      const serializedOracleCall = await buildCall();
      const [msgNonce, requestId] = await proxy.initiateOracleCall.staticCall(
        other.address, gasAmount, maxBridgeFee, serializedOracleCall, maxMsgFee, false,
        { value: totalValue }
      );
      expect(requestId).to.equal(0n);
      expect(msgNonce).to.equal(1n); // first nonce from MockMessageBridge
    });
  });

  // ── Ownable ─────────────────────────────────────────────────────────────────

  describe("Ownable", () => {
    it("owner() returns the deployer address", async () => {
      expect(await proxy.owner()).to.equal(owner.address);
    });

    it("transferOwnership transfers to a new owner", async () => {
      await proxy.connect(owner).transferOwnership(other.address);
      expect(await proxy.owner()).to.equal(other.address);
    });

    it("non-owner cannot call transferOwnership", async () => {
      await expect(
        proxy.connect(other).transferOwnership(other.address)
      ).to.be.revertedWithCustomError(proxy, "OwnableUnauthorizedAccount");
    });
  });

  // ── UUPS Upgradability ───────────────────────────────────────────────────────

  describe("Upgradeability (UUPS)", () => {
    it("only owner can upgrade the implementation", async () => {
      const OracleProxyV2 = await ethers.getContractFactory("OracleProxy", other);
      await expect(
        upgrades.upgradeProxy(await proxy.getAddress(), OracleProxyV2, { kind: "uups" })
      ).to.be.revertedWithCustomError(proxy, "OwnableUnauthorizedAccount");
    });

    it("owner can upgrade; proxy address stays the same and state is preserved", async () => {
      // Store a result before upgrade
      await proxy.onOracleResult(1n, ethers.toUtf8Bytes("pre-upgrade"));

      const proxyAddress = await proxy.getAddress();

      // Upgrade to a new implementation (same bytecode — tests the proxy mechanism)
      const OracleProxyV2 = await ethers.getContractFactory("OracleProxy", owner);
      const upgraded = (await upgrades.upgradeProxy(
        proxyAddress,
        OracleProxyV2,
        { kind: "uups" }
      )) as unknown as OracleProxy;

      // Proxy address is unchanged
      expect(await upgraded.getAddress()).to.equal(proxyAddress);

      // Ownership and addresses are preserved
      expect(await upgraded.owner()).to.equal(owner.address);
      expect(await upgraded.bridge()).to.equal(await mockBridge.getAddress());

      // State (oracle result) survived the upgrade
      const [result, exists] = await upgraded.getOracleResult(1n);
      expect(exists).to.be.true;
      expect(result).to.equal(ethers.hexlify(ethers.toUtf8Bytes("pre-upgrade")));
    });
  });
});
