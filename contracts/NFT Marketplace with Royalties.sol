// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title NFT Marketplace with Royalties
 * @dev A decentralized marketplace for NFTs with automatic royalty distribution
 */
contract Project is ERC721, ERC721URIStorage, Ownable, ReentrancyGuard, IERC721Receiver {
    
    // Marketplace fee (2.5%)
    uint256 public constant MARKETPLACE_FEE = 250; // 250 basis points = 2.5%
    uint256 public constant BASIS_POINTS = 10000;
    
    // Token counter
    uint256 private _tokenIdCounter;
    
    // Royalty info for each token
    struct RoyaltyInfo {
        address creator;
        uint256 percentage; // in basis points (100 = 1%)
    }
    
    // Listing info for marketplace
    struct Listing {
        address seller;
        uint256 price;
        bool active;
    }
    
    // Mappings
    mapping(uint256 => RoyaltyInfo) private _royalties;
    mapping(uint256 => Listing) private _listings;
    mapping(address => uint256) private _earnings;
    
    // Events  
    event NFTMinted(uint256 indexed tokenId, address indexed creator, string tokenURI, uint256 royaltyPercentage);
    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event NFTDelisted(uint256 indexed tokenId, address indexed seller);
    event RoyaltyPaid(uint256 indexed tokenId, address indexed creator, uint256 amount);
    
    constructor() ERC721("NFT Marketplace", "NFTM") Ownable(msg.sender) {}
    
    /**
     * @dev Core Function 1: Mint NFT with royalty information
     * @param to The address to mint the NFT to
     * @param tokenURI The metadata URI for the NFT
     * @param royaltyPercentage The royalty percentage for the creator (in basis points)
     */
    function mintNFT(
        address to,
        string memory tokenURI,
        uint256 royaltyPercentage
    ) public returns (uint256) {
        require(royaltyPercentage <= 1000, "Royalty cannot exceed 10%"); // Max 10% royalty
        require(bytes(tokenURI).length > 0, "Token URI cannot be empty");
        
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        
        // Set royalty info
        _royalties[tokenId] = RoyaltyInfo({
            creator: to,
            percentage: royaltyPercentage
        });
        
        emit NFTMinted(tokenId, to, tokenURI, royaltyPercentage);
        return tokenId;
    }
    
    /**
     * @dev Core Function 2: List NFT for sale
     * @param tokenId The ID of the NFT to list
     * @param price The price to list the NFT for (in wei)
     */
    function listNFT(uint256 tokenId, uint256 price) public {
        require(ownerOf(tokenId) == msg.sender, "Only owner can list NFT");
        require(price > 0, "Price must be greater than 0");
        require(!_listings[tokenId].active, "NFT already listed");
        
        // Transfer NFT to contract for escrow
        safeTransferFrom(msg.sender, address(this), tokenId);
        
        _listings[tokenId] = Listing({
            seller: msg.sender,
            price: price,
            active: true
        });
        
        emit NFTListed(tokenId, msg.sender, price);
    }
    
    /**
     * @dev Core Function 3: Purchase NFT with automatic royalty distribution
     * @param tokenId The ID of the NFT to purchase
     */
    function purchaseNFT(uint256 tokenId) public payable nonReentrant {
        Listing memory listing = _listings[tokenId];
        require(listing.active, "NFT not listed for sale");
        require(msg.value >= listing.price, "Insufficient payment");
        
        address seller = listing.seller;
        uint256 price = listing.price;
        
        // Mark as sold first to prevent re-entrancy
        _listings[tokenId].active = false;
        
        // Calculate fees and royalties
        uint256 marketplaceFee = (price * MARKETPLACE_FEE) / BASIS_POINTS;
        uint256 royaltyAmount = 0;
        address creator = _royalties[tokenId].creator;
        
        // Only pay royalty if seller is not the original creator
        if (seller != creator) {
            royaltyAmount = (price * _royalties[tokenId].percentage) / BASIS_POINTS;
        }
        
        uint256 sellerAmount = price - marketplaceFee - royaltyAmount;
        
        // Transfer NFT to buyer
        _safeTransfer(address(this), msg.sender, tokenId, "");
        
        // Distribute payments
        _earnings[owner()] += marketplaceFee; // Marketplace fee to contract owner
        _earnings[seller] += sellerAmount;    // Seller gets remaining amount
        
        if (royaltyAmount > 0) {
            _earnings[creator] += royaltyAmount;
            emit RoyaltyPaid(tokenId, creator, royaltyAmount);
        }
        
        // Refund excess payment
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
        
        emit NFTSold(tokenId, seller, msg.sender, price);
    }
    
    /**
     * @dev Remove NFT from marketplace
     * @param tokenId The ID of the NFT to delist
     */
    function delistNFT(uint256 tokenId) public {
        require(_listings[tokenId].seller == msg.sender, "Only seller can delist");
        require(_listings[tokenId].active, "NFT not listed");
        
        _listings[tokenId].active = false;
        
        // Return NFT to seller
        _safeTransfer(address(this), msg.sender, tokenId, "");
        
        emit NFTDelisted(tokenId, msg.sender);
    }
    
    /**
     * @dev Withdraw earnings
     */
    function withdrawEarnings() public nonReentrant {
        uint256 amount = _earnings[msg.sender];
        require(amount > 0, "No earnings to withdraw");
        
        _earnings[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }
    
    // View functions
    function getListing(uint256 tokenId) public view returns (Listing memory) {
        return _listings[tokenId];
    }
    
    function getRoyaltyInfo(uint256 tokenId) public view returns (address, uint256) {
        RoyaltyInfo memory royalty = _royalties[tokenId];
        return (royalty.creator, royalty.percentage);
    }
    
    function getEarnings(address user) public view returns (uint256) {
        return _earnings[user];
    }
    
    function getTotalSupply() public view returns (uint256) {
        return _tokenIdCounter;
    }
    
    // Required overrides
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
