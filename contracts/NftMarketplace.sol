// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error NftMarketPlace__PriceMustBeAbovevZero();
error NftMarketPlace__NotApprovedForMarketplace();
error NftMarketPlace__AlreadyListed(address nftAddress, uint256 tokenId);
error NftMarketPlace__NotListed(address nftAddress, uint256 tokenId);
error NftMarketPlace__PriceNotMet(
    address nftAddress,
    uint256 tokenId,
    uint256 price
);

error NftMarketPlace__NotOwner();
error NftMarketPlace__NoProceeds();
error NftMarketPlace__TransferFailed();

contract NftMarketPlace is ReentrancyGuard {
    struct Listing {
        uint256 price;
        address seller;
    }

    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    event ItemCanceled(
        address indexed owner,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    event ItemBought(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    // NFT Contract address -> NFT TokenID -> Listing
    mapping(address => mapping(uint256 => Listing)) private s_listings;

    // Seller address -> Amount earned
    mapping(address => uint256) private s_proceeds;

    ////////////////////
    // Modifers       //
    ////////////////////
    modifier notListed(
        address nftAddress,
        uint256 tokenId,
        address owner
    ) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price > 0) {
            revert NftMarketPlace__AlreadyListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price <= 0) {
            revert NftMarketPlace__NotListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isOwner(
        address nftAddress,
        uint256 tokenId,
        address spender
    ) {
        IERC721 nft = IERC721(nftAddress);
        address owner = nft.ownerOf(tokenId);
        if (spender != owner) {
            revert NftMarketPlace__NotOwner();
        }
        _;
    }

    ////////////////////
    // Main Functions //
    ////////////////////

    /*
     * @notice Method ofr listing your NFT on the marketplace
     * @param nftAddress: Address of the NFT
     * @param tokenId: The Token ID of the NFT
     * @param price: sale price of the listed NFT
     * @dev Tecnically, we could have the contract be the escrow for the NFTs
     * but this way people can still hold their NFTs when listed.
     */
    function listItem(
        address nftAddress,
        uint256 tokenId,
        uint256 price
    )
        external
        notListed(nftAddress, tokenId, msg.sender)
        isOwner(nftAddress, tokenId, msg.sender)
    {
        if (price <= 0) {
            revert NftMarketPlace__PriceMustBeAbovevZero();
        }

        // 1. Send the NFT to the contract. Transfer -> Contract "hold" the NFT.abi
        // 2. Owners can still hold their NFT, and give the marketplace approval
        // to sell the NFT for them.

        IERC721 nft = IERC721(nftAddress);
        if (nft.getApproved(tokenId) != address(this)) {
            revert NftMarketPlace__NotApprovedForMarketplace();
        }

        s_listings[nftAddress][tokenId] = Listing(price, msg.sender);
        emit ItemListed(msg.sender, nftAddress, tokenId, price);
    }

    function buyItem(
        address nftAddress,
        uint256 tokenId
    ) external payable isListed(nftAddress, tokenId) nonReentrant {
        Listing memory listedItem = s_listings[nftAddress][tokenId];
        if (msg.value < listedItem.price) {
            revert NftMarketPlace__PriceNotMet(
                nftAddress,
                tokenId,
                listedItem.price
            );
        }

        // We don't just send the seller the money...?
        s_proceeds[listedItem.seller] =
            s_proceeds[listedItem.seller] +
            msg.value;

        delete (s_listings[nftAddress][tokenId]);
        IERC721(nftAddress).safeTransferFrom(
            listedItem.seller,
            msg.sender,
            tokenId
        );

        emit ItemBought(msg.sender, nftAddress, tokenId, listedItem.price);
    }

    function cancelListing(
        address nftAddress,
        uint256 tokenId
    )
        external
        isOwner(nftAddress, tokenId, msg.sender)
        isListed(nftAddress, tokenId)
    {
        delete (s_listings[nftAddress][tokenId]);
        emit ItemCanceled(msg.sender, nftAddress, tokenId);
    }

    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice
    )
        external
        isListed(nftAddress, tokenId)
        isOwner(nftAddress, tokenId, msg.sender)
    {
        s_listings[nftAddress][tokenId].price = newPrice;
        emit ItemListed(msg.sender, nftAddress, tokenId, newPrice);
    }

    function withdrawProceeds() external nonReentrant {
        uint256 proceeds = s_proceeds[msg.sender];
        if (proceeds <= 0) {
            revert NftMarketPlace__NoProceeds();
        }

        s_proceeds[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: proceeds}("");
        if (!success) {
            revert NftMarketPlace__TransferFailed();
        }
    }

    //////////////////////
    // Getter Functions //
    //////////////////////


    function getListing(address nftAddress, uint256 tokenId)
    external
    view
    returns (Listing memory) {
        return s_listings[nftAddress][tokenId];
    }

    function getProceeds(address seller) external view returns (uint256) {
        return s_proceeds[seller];
    }
}

// 1. `listItem`: List NFTs on the marketplace
// 2. `buyItem`: Buy the NFTs
// 3. `cancelItem`: Cancel a listing
// 4. `updateListing`: Update Price
// 5. `withdrawProceeds`: Withdraw payment for my bught NFTs
