// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Time-Locked Social Recovery Wallet with Reputation System
 * @dev A smart contract wallet with social recovery mechanisms and guardian reputation tracking
 */
contract Project {
    // Structs
    struct Guardian {
        address guardianAddress;
        uint256 reputationScore;
        uint256 totalRecoveries;
        uint256 successfulRecoveries;
        bool isActiv
        uint256 stakedAmount;
    }

    struct RecoveryRequest {
        address newOwner;
        uint256 requestTime
        uint256 requiredVotes;
        uint256 currentVotes;
        mapping(address => bool) hasVoted;
        mapping(address => bytes32) commitments;
        bool isExecuted;
        bool isActive;
        RecoveryType recoveryType;struct RecoveryRequest {
        address newOwner;
        uint256 requestTime
        uint256 requiredVotes;
        uint256 currentVotes;
        mapping(address => bool) hasVoted;
        mapping(address => bytes32) commitments;
        bool isExecuted;
        bool isActive;
        RecoveryType recoveryType;
    }

    enum RecoveryType {
        LOST_KEY,      // 7 days wait
        COMPROMISED,   // 1 day wait
        EMERGENCY      // Immediate with majority
    }

    // State
    address public owner;
    mapping(address => Guardian) public guardians;
    address[] public guardianList;
    mapping(uint256 => RecoveryRequest) public recoveryRequests;
    uint256 public recoveryRequestCount;
    uint256 public constant MINIMUM_GUARDIANS = 1; // ✅ changed from 3 to 1
    uint256 public constant STAKE_AMOUNT = 0.1 ether;
    uint256 public constant BASE_REPUTATION = 100;

    // Time locks for different recovery types
    mapping(RecoveryType => uint256) public timeLocks;

    // Events
    event GuardianAdded(address indexed guardian, uint256 initialReputation);
    event GuardianRemoved(address indexed guardian);
    event RecoveryRequested(uint256 indexed requestId, address indexed newOwner, RecoveryType recoveryType);
    event RecoveryVoteCast(uint256 indexed requestId, address indexed guardian);
    event RecoveryExecuted(uint256 indexed requestId, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyGuardian() {
        require(guardians[msg.sender].isActive, "Only active guardians can call this function");
        _;
    }

    modifier validRecoveryRequest(uint256 _requestId) {
        require(_requestId < recoveryRequestCount, "Invalid recovery request ID");
        require(recoveryRequests[_requestId].isActive, "Recovery request is not active");
        require(!recoveryRequests[_requestId].isExecuted, "Recovery request already executed");
        _;
    }

    /**
     * @dev Constructor to initialize the wallet with initial owner
     * @param _initialGuardians Array of initial guardian addresses
     */
    constructor(address[] memory _initialGuardians) {
        require(_initialGuardians.length >= MINIMUM_GUARDIANS, "Minimum 1 guardian required");
        
        owner = msg.sender;
        
        // Initialize time locks
        timeLocks[RecoveryType.LOST_KEY] = 7 days;
        timeLocks[RecoveryType.COMPROMISED] = 1 days;
        timeLocks[RecoveryType.EMERGENCY] = 0;

        // Add initial guardians
        for (uint256 i = 0; i < _initialGuardians.length; i++) {
            _addGuardian(_initialGuardians[i]);
        }
    }

    function addGuardian(address _guardian) external onlyOwner {
        require(_guardian != address(0), "Invalid guardian address");
        require(_guardian != owner, "Owner cannot be a guardian");
        require(!guardians[_guardian].isActive, "Guardian already exists");

        _addGuardian(_guardian);
    }

    function requestRecovery(address _newOwner, RecoveryType _recoveryType) external onlyGuardian {
        require(_newOwner != address(0), "Invalid new owner address");
        require(_newOwner != owner, "New owner cannot be current owner");

        uint256 totalReputation = _getTotalActiveReputation();
        uint256 requiredReputation = (totalReputation * 60) / 100;

        RecoveryRequest storage request = recoveryRequests[recoveryRequestCount];
        request.newOwner = _newOwner;
        request.requestTime = block.timestamp;
        request.requiredVotes = requiredReputation;
        request.currentVotes = 0;
        request.isExecuted = false;
        request.isActive = true;
        request.recoveryType = _recoveryType;

        emit RecoveryRequested(recoveryRequestCount, _newOwner, _recoveryType);
        recoveryRequestCount++;
    }

    function voteOnRecovery(uint256 _requestId, bool _support) 
        external 
        onlyGuardian 
        validRecoveryRequest(_requestId) 
        payable 
    {
        RecoveryRequest storage request = recoveryRequests[_requestId];
        require(!request.hasVoted[msg.sender], "Guardian has already voted");
        require(msg.value >= STAKE_AMOUNT, "Insufficient stake amount");

        uint256 timeRequired = timeLocks[request.recoveryType];
        if (request.recoveryType != RecoveryType.EMERGENCY) {
            require(block.timestamp >= request.requestTime + timeRequired, "Time lock not yet expired");
        }

        request.hasVoted[msg.sender] = true;
        guardians[msg.sender].stakedAmount += msg.value;

        if (_support) {
            uint256 voteWeight = guardians[msg.sender].reputationScore;
            request.currentVotes += voteWeight;

            emit RecoveryVoteCast(_requestId, msg.sender);

            if (request.currentVotes >= request.requiredVotes) {
                _executeRecovery(_requestId);
            }
        }
    }

    function _addGuardian(address _guardian) internal {
        guardians[_guardian] = Guardian({
            guardianAddress: _guardian,
            reputationScore: BASE_REPUTATION,
            totalRecoveries: 0,
            successfulRecoveries: 0,
            isActive: true,
            stakedAmount: 0
        });
        
        guardianList.push(_guardian);
        emit GuardianAdded(_guardian, BASE_REPUTATION);
    }

    function _executeRecovery(uint256 _requestId) internal {
        RecoveryRequest storage request = recoveryRequests[_requestId];
        request.isExecuted = true;
        request.isActive = false;

        address previousOwner = owner;
        owner = request.newOwner;

        _updateGuardianReputations(_requestId, true);

        emit RecoveryExecuted(_requestId, request.newOwner);
        emit OwnershipTransferred(previousOwner, request.newOwner);
    }

    function _updateGuardianReputations(uint256 _requestId, bool _successful) internal {
        RecoveryRequest storage request = recoveryRequests[_requestId];
        
        for (uint256 i = 0; i < guardianList.length; i++) {
            address guardianAddr = guardianList[i];
            if (request.hasVoted[guardianAddr]) {
                Guardian storage guardian = guardians[guardianAddr];
                guardian.totalRecoveries++;
                
                if (_successful) {
                    guardian.successfulRecoveries++;
                    guardian.reputationScore += 10;
                    payable(guardianAddr).transfer(guardian.stakedAmount + 0.01 ether);
                } else {
                    guardian.reputationScore = guardian.reputationScore > 20 ? 
                        guardian.reputationScore - 20 : 0;
                }
                
                guardian.stakedAmount = 0;
            }
        }
    }

    function _getTotalActiveReputation() internal view returns (uint256) {
        uint256 totalReputation = 0;
        for (uint256 i = 0; i < guardianList.length; i++) {
            if (guardians[guardianList[i]].isActive) {
                totalReputation += guardians[guardianList[i]].reputationScore;
            }
        }
        return totalReputation;
    }

    function getGuardian(address _guardian) external view returns (Guardian memory) {
        return guardians[_guardian];
    }

    function getAllGuardians() external view returns (address[] memory) {
        return guardianList;
    }

    function getRecoveryRequest(uint256 _requestId) external view returns (
        address newOwner,
        uint256 requestTime,
        uint256 requiredVotes,
        uint256 currentVotes,
        bool isExecuted,
        bool isActive,
        RecoveryType recoveryType
    ) {
        RecoveryRequest storage request = recoveryRequests[_requestId];
        return (
            request.newOwner,
            request.requestTime,
            request.requiredVotes,
            request.currentVotes,
            request.isExecuted,
            request.isActive,
            request.recoveryType
        );
    }

    receive() external payable {}
    fallback() external payable {}
}
