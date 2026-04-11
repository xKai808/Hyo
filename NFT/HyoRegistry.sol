// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ============================================================
//  HYO AGENT REGISTRY
//  Version: 1.0.0
//  Standard: HYO-1
//
//  IMPORTANT: This contract must be professionally audited
//  before mainnet deployment. Do not deploy to mainnet
//  without a security audit.
// ============================================================

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract HyoRegistry is ERC721, ERC721Royalty, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ============================================================
    //  CONSTANTS
    // ============================================================

    // 5% royalty on secondary sales
    uint96 public constant ROYALTY_FEE = 500;

    // 90-day hold period after lapse or revocation (in seconds)
    uint256 public constant HOLD_PERIOD = 90 days;

    // 135-day permanent release (90 + 45 day buffer)
    uint256 public constant RELEASE_PERIOD = 135 days;

    // ============================================================
    //  STATE
    // ============================================================

    // Token ID counter — starts at 1, aether.hyo = #0001
    uint256 private _nextTokenId = 1;

    // Platform address — authorized to call admin functions
    address public platform;

    // Base URI for off-chain metadata JSON files
    string private _baseTokenURI;

    // Agent status enum
    enum Status {
        Active,       // Fully verified and operational
        Suspended,    // Temporarily inactive (payment lapse or review)
        Revoked       // Permanently invalidated
    }

    // ============================================================
    //  MAPPINGS
    // ============================================================

    // name → tokenId  (e.g., "aether" → 1)
    mapping(string => uint256) public nameToTokenId;

    // tokenId → name
    mapping(uint256 => string) public tokenIdToName;

    // tokenId → endpoint URL
    mapping(uint256 => string) public tokenEndpoint;

    // tokenId → current status
    mapping(uint256 => Status) public tokenStatus;

    // tokenId → suspension reason (for transparency)
    mapping(uint256 => string) public suspensionReason;

    // name → hold expiry timestamp (after lapse/revocation)
    mapping(string => uint256) public nameHoldExpiry;

    // name → original owner during hold period
    mapping(string => address) public nameHoldOriginalOwner;

    // name → whether lapse was permanent revocation or payment lapse
    mapping(string => bool) public namePermanentlyRevoked;

    // tokenId → registration timestamp
    mapping(uint256 => uint256) public registrationDate;

    // ============================================================
    //  EVENTS
    // ============================================================

    event AgentRegistered(
        uint256 indexed tokenId,
        string name,
        address indexed owner,
        string endpoint
    );

    event AgentSuspended(
        uint256 indexed tokenId,
        string name,
        string reason
    );

    event AgentRestored(
        uint256 indexed tokenId,
        string name
    );

    event AgentPermanentlyRevoked(
        uint256 indexed tokenId,
        string name
    );

    event AgentLapsed(
        uint256 indexed tokenId,
        string name
    );

    event EndpointUpdated(
        uint256 indexed tokenId,
        string name,
        string newEndpoint
    );

    event NameReleased(
        string name,
        uint256 indexed previousTokenId
    );

    event PlatformUpdated(
        address indexed previousPlatform,
        address indexed newPlatform
    );

    // ============================================================
    //  MODIFIERS
    // ============================================================

    modifier onlyPlatform() {
        require(
            msg.sender == platform || msg.sender == owner(),
            "HYO: Not authorized"
        );
        _;
    }

    modifier tokenExists(uint256 tokenId) {
        require(tokenId > 0 && tokenId < _nextTokenId, "HYO: Token does not exist");
        _;
    }

    modifier nameAvailable(string calldata name) {
        uint256 existingId = nameToTokenId[name];
        if (existingId != 0) {
            // Name exists — only allowed if revoked AND hold expired
            require(
                tokenStatus[existingId] == Status.Revoked &&
                block.timestamp > nameHoldExpiry[name],
                "HYO: Name not available"
            );
        }
        _;
    }

    // ============================================================
    //  CONSTRUCTOR
    // ============================================================

    constructor(
        address platformAddress,
        address royaltyReceiver,
        string memory baseURI
    )
        ERC721("Hyo Agent Registry", "HYO")
        Ownable(msg.sender)
    {
        require(platformAddress != address(0), "HYO: Invalid platform address");
        require(royaltyReceiver != address(0), "HYO: Invalid royalty receiver");

        platform = platformAddress;
        _baseTokenURI = baseURI;

        // Set default royalty: 5% to royaltyReceiver on all secondary sales
        _setDefaultRoyalty(royaltyReceiver, ROYALTY_FEE);
    }

    // ============================================================
    //  CORE REGISTRY FUNCTIONS
    // ============================================================

    /**
     * @notice Register a new .hyo agent name and mint the NFT.
     * @dev Called by the platform backend after background check passes
     *      and Stripe payment is confirmed. The NFT is minted directly
     *      to the agent owner's ETH wallet.
     *
     * @param name      The .hyo name being registered (e.g., "aether")
     * @param endpoint  The agent's endpoint URL
     * @param owner     The ETH address that will receive the NFT
     * @return tokenId  The minted token ID
     */
    function register(
        string calldata name,
        string calldata endpoint,
        address owner
    )
        external
        onlyPlatform
        nonReentrant
        nameAvailable(name)
        returns (uint256 tokenId)
    {
        require(bytes(name).length > 0, "HYO: Name cannot be empty");
        require(bytes(name).length <= 64, "HYO: Name too long");
        require(bytes(endpoint).length > 0, "HYO: Endpoint cannot be empty");
        require(owner != address(0), "HYO: Invalid owner address");
        require(_isValidName(name), "HYO: Invalid name characters");

        tokenId = _nextTokenId++;

        // If re-registering a previously lapsed name, clear old record
        uint256 existingId = nameToTokenId[name];
        if (existingId != 0) {
            delete tokenIdToName[existingId];
            delete tokenEndpoint[existingId];
            delete nameHoldExpiry[name];
            delete nameHoldOriginalOwner[name];
            delete namePermanentlyRevoked[name];
        }

        // Mint the NFT
        _safeMint(owner, tokenId);

        // Store registration data
        nameToTokenId[name] = tokenId;
        tokenIdToName[tokenId] = name;
        tokenEndpoint[tokenId] = endpoint;
        tokenStatus[tokenId] = Status.Active;
        registrationDate[tokenId] = block.timestamp;

        emit AgentRegistered(tokenId, name, owner, endpoint);

        return tokenId;
    }

    /**
     * @notice Resolve a .hyo name to its endpoint and status.
     * @dev Called by any agent or system querying the registry.
     *      Returns endpoint only — callers should check status
     *      before trusting the endpoint.
     *
     * @param name  The .hyo name to resolve
     * @return endpoint      The agent's endpoint URL
     * @return status        Current status (Active/Suspended/Revoked)
     * @return agentOwner    Current NFT owner's ETH address
     * @return tokenId       The NFT token ID
     * @return registered    Unix timestamp of registration
     */
    function resolve(string calldata name)
        external
        view
        returns (
            string memory endpoint,
            Status status,
            address agentOwner,
            uint256 tokenId,
            uint256 registered
        )
    {
        tokenId = nameToTokenId[name];
        require(tokenId != 0, "HYO: Name not registered");

        return (
            tokenEndpoint[tokenId],
            tokenStatus[tokenId],
            ownerOf(tokenId),
            tokenId,
            registrationDate[tokenId]
        );
    }

    /**
     * @notice Check if a token is currently valid and active.
     * @dev The primary trust check other agents should call.
     *      Returns false if suspended, revoked, or non-existent.
     */
    function isValid(uint256 tokenId)
        external
        view
        tokenExists(tokenId)
        returns (bool)
    {
        return tokenStatus[tokenId] == Status.Active;
    }

    /**
     * @notice Check if a name is available for registration.
     */
    function isNameAvailable(string calldata name)
        external
        view
        returns (bool available, uint256 holdExpiresAt)
    {
        uint256 existingId = nameToTokenId[name];

        if (existingId == 0) {
            return (true, 0);
        }

        if (tokenStatus[existingId] == Status.Revoked) {
            uint256 expiry = nameHoldExpiry[name];
            return (block.timestamp > expiry, expiry);
        }

        return (false, 0);
    }

    // ============================================================
    //  OWNER-CALLABLE FUNCTIONS
    // ============================================================

    /**
     * @notice Update the agent's endpoint URL.
     * @dev Only the NFT owner can call this.
     *      Updating endpoint triggers re-verification in the backend.
     *      Agent is automatically moved to Suspended status by the
     *      platform during re-verification (handled off-chain).
     */
    function updateEndpoint(uint256 tokenId, string calldata newEndpoint)
        external
        tokenExists(tokenId)
    {
        require(ownerOf(tokenId) == msg.sender, "HYO: Not token owner");
        require(tokenStatus[tokenId] != Status.Revoked, "HYO: Token revoked");
        require(bytes(newEndpoint).length > 0, "HYO: Endpoint cannot be empty");

        string memory name = tokenIdToName[tokenId];
        tokenEndpoint[tokenId] = newEndpoint;

        emit EndpointUpdated(tokenId, name, newEndpoint);
    }

    // ============================================================
    //  PLATFORM-CALLABLE ADMIN FUNCTIONS
    // ============================================================

    /**
     * @notice Suspend an agent.
     * @dev Called when:
     *      - Payment lapses (before permanent lapse)
     *      - Background check re-run fails
     *      - Dispute filed pending investigation
     *      - Anomaly detected
     *
     *      Suspended agents cannot resolve. Subscription paused.
     *      Reversible via restore().
     */
    function suspend(uint256 tokenId, string calldata reason)
        external
        onlyPlatform
        tokenExists(tokenId)
    {
        require(tokenStatus[tokenId] == Status.Active, "HYO: Not active");

        string memory name = tokenIdToName[tokenId];
        tokenStatus[tokenId] = Status.Suspended;
        suspensionReason[tokenId] = reason;

        emit AgentSuspended(tokenId, name, reason);
    }

    /**
     * @notice Restore a suspended agent to active status.
     * @dev Called when:
     *      - Payment is resolved
     *      - Re-verification passes
     *      - Investigation cleared
     */
    function restore(uint256 tokenId)
        external
        onlyPlatform
        tokenExists(tokenId)
    {
        require(tokenStatus[tokenId] == Status.Suspended, "HYO: Not suspended");

        string memory name = tokenIdToName[tokenId];
        tokenStatus[tokenId] = Status.Active;
        delete suspensionReason[tokenId];

        emit AgentRestored(tokenId, name);
    }

    /**
     * @notice Permanently revoke an agent for serious violations.
     * @dev Irreversible. Called when:
     *      - Fraudulent registration confirmed
     *      - Sanctions match discovered
     *      - Severe/sustained malicious behavior
     *
     *      Name enters 90-day hold. Original owner has priority
     *      to appeal. After 135 days, name is released to pool.
     *      NFT remains on-chain as permanent record — marked Revoked.
     */
    function permanentlyRevoke(uint256 tokenId)
        external
        onlyPlatform
        tokenExists(tokenId)
    {
        require(tokenStatus[tokenId] != Status.Revoked, "HYO: Already revoked");

        string memory name = tokenIdToName[tokenId];
        address currentOwner = ownerOf(tokenId);

        tokenStatus[tokenId] = Status.Revoked;
        namePermanentlyRevoked[name] = true;
        nameHoldExpiry[name] = block.timestamp + HOLD_PERIOD;
        nameHoldOriginalOwner[name] = currentOwner;

        emit AgentPermanentlyRevoked(tokenId, name);
    }

    /**
     * @notice Lapse an agent due to non-payment after grace period.
     * @dev Different from permanentRevoke — this is non-payment,
     *      not a violation. Original owner gets 90-day priority
     *      to reclaim by paying outstanding balance.
     *      After 135 days, name released to general pool.
     */
    function lapse(uint256 tokenId)
        external
        onlyPlatform
        tokenExists(tokenId)
    {
        require(tokenStatus[tokenId] != Status.Revoked, "HYO: Already revoked");

        string memory name = tokenIdToName[tokenId];
        address currentOwner = ownerOf(tokenId);

        tokenStatus[tokenId] = Status.Revoked;
        namePermanentlyRevoked[name] = false;
        nameHoldExpiry[name] = block.timestamp + HOLD_PERIOD;
        nameHoldOriginalOwner[name] = currentOwner;

        emit AgentLapsed(tokenId, name);
    }

    /**
     * @notice Update the platform address.
     * @dev Only contract owner. For platform upgrades.
     */
    function setPlatform(address newPlatform) external onlyOwner {
        require(newPlatform != address(0), "HYO: Invalid address");
        emit PlatformUpdated(platform, newPlatform);
        platform = newPlatform;
    }

    /**
     * @notice Update the base URI for metadata.
     * @dev Only contract owner. Points to off-chain JSON metadata.
     */
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    /**
     * @notice Update royalty receiver address.
     * @dev Only contract owner.
     */
    function updateRoyaltyReceiver(address newReceiver) external onlyOwner {
        require(newReceiver != address(0), "HYO: Invalid address");
        _setDefaultRoyalty(newReceiver, ROYALTY_FEE);
    }

    // ============================================================
    //  VIEW FUNCTIONS
    // ============================================================

    /**
     * @notice Total number of agents ever registered.
     */
    function totalRegistered() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    /**
     * @notice Get full agent record by token ID.
     */
    function getAgent(uint256 tokenId)
        external
        view
        tokenExists(tokenId)
        returns (
            string memory name,
            string memory endpoint,
            Status status,
            address agentOwner,
            uint256 registered,
            string memory suspension
        )
    {
        return (
            tokenIdToName[tokenId],
            tokenEndpoint[tokenId],
            tokenStatus[tokenId],
            ownerOf(tokenId),
            registrationDate[tokenId],
            suspensionReason[tokenId]
        );
    }

    // ============================================================
    //  INTERNAL FUNCTIONS
    // ============================================================

    /**
     * @notice Validate name characters.
     * @dev Only lowercase letters, numbers, and hyphens allowed.
     *      Cannot start or end with a hyphen.
     *      Mirrors standard domain name rules.
     */
    function _isValidName(string calldata name) internal pure returns (bool) {
        bytes memory b = bytes(name);
        uint256 len = b.length;

        if (len == 0 || len > 64) return false;

        // Cannot start or end with hyphen
        if (b[0] == 0x2D || b[len - 1] == 0x2D) return false;

        for (uint256 i = 0; i < len; i++) {
            bytes1 char = b[i];
            bool isLower = (char >= 0x61 && char <= 0x7A);   // a-z
            bool isDigit = (char >= 0x30 && char <= 0x39);   // 0-9
            bool isHyphen = (char == 0x2D);                   // -

            if (!isLower && !isDigit && !isHyphen) return false;
        }

        return true;
    }

    // ============================================================
    //  REQUIRED OVERRIDES
    // ============================================================

    function tokenURI(uint256 tokenId)
        public
        view
        override
        tokenExists(tokenId)
        returns (string memory)
    {
        return string(
            abi.encodePacked(_baseTokenURI, tokenId.toString(), ".json")
        );
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Royalty)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
