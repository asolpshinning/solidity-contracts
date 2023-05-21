const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Whitelist-related Functions Testing", function () {
    async function setupERC1410Whitelist() {
        const [owner, addr1, addr2] = await ethers.getSigners();

        const ShareToken = await ethers.getContractFactory("ERC1410Standard");
        const shareToken = await ShareToken.deploy();

        return { owner, addr1, addr2, shareToken };
    }

    describe("Deployment", function () {
        it("Should add the deployer to the whitelist", async function () {
            const { owner, shareToken } = await setupERC1410Whitelist();
            expect(await shareToken.isWhitelisted(owner.address)).to.equal(true);
        });
    });

    describe("Manage Whitelist", function () {
        it("Should allow the owner to add an address to the whitelist", async function () {
            const { owner, addr1, addr2, shareToken } = await setupERC1410Whitelist();
            await shareToken.connect(owner).addToWhitelist(addr1.address);
            expect(await shareToken.isWhitelisted(addr1.address)).to.equal(true);
        });

        it("Should not allow non-owner to add an address to the whitelist", async function () {
            const { owner, addr1, addr2, shareToken } = await setupERC1410Whitelist();
            await expect(shareToken.connect(addr1).addToWhitelist(addr1.address)).to.be.revertedWith("Caller is not the owner or manager");
        });
        it("Should allow the owner to remove an address from the whitelist", async function () {
            const { owner, addr1, addr2, shareToken } = await setupERC1410Whitelist();
            await shareToken.connect(owner).addToWhitelist(addr1.address);
            await shareToken.connect(owner).removeFromWhitelist(addr1.address);
            expect(await shareToken.isWhitelisted(addr1.address)).to.equal(false);
        });
        it("Should not allow non-owner to remove an address from the whitelist", async function () {
            const { owner, addr1, addr2, shareToken } = await setupERC1410Whitelist();
            await shareToken.connect(owner).addToWhitelist(addr1.address);
            await expect(shareToken.connect(addr1).removeFromWhitelist(addr1.address)).to.be.revertedWith("Caller is not the owner or manager");
        });
        it("should add a manager to the whitelist when owner adds a manager", async function () {
            const { owner, addr1, addr2, shareToken } = await setupERC1410Whitelist();
            await shareToken.connect(owner).addManager(addr1.address);
            expect(await shareToken.isManager(addr1.address)).to.equal(true);
            expect(await shareToken.isWhitelisted(addr1.address)).to.equal(true);
        });
        it("should remove a manager from the whitelist when owner removes a manager", async function () {
            const { owner, addr1, addr2, shareToken } = await setupERC1410Whitelist();
            await shareToken.connect(owner).addManager(addr1.address);
            await shareToken.connect(owner).removeManager(addr1.address);
            expect(await shareToken.isManager(addr1.address)).to.equal(false);
            expect(await shareToken.isWhitelisted(addr1.address)).to.equal(false);
        });
        it("should allow a manager to remove an address from the whitelist", async function () {
            const { owner, addr1, addr2, shareToken } = await setupERC1410Whitelist();
            await shareToken.connect(owner).addManager(addr1.address);
            await shareToken.connect(addr1).removeFromWhitelist(owner.address);
            expect(await shareToken.isWhitelisted(owner.address)).to.equal(false);
        });
        it("should allow a manager to add an address to the whitelist", async function () {
            const { owner, addr1, addr2, shareToken } = await setupERC1410Whitelist();
            await shareToken.connect(owner).addManager(addr1.address);
            await shareToken.connect(addr1).addToWhitelist(addr2.address);
            expect(await shareToken.isWhitelisted(addr2.address)).to.equal(true);
        });

    });

});
