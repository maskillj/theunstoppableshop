// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

// Gas limit 500,000

contract UnlockOracleClient is ChainlinkClient {
    using Chainlink for Chainlink.Request;

    struct Request {
        uint256 requestId;
        bytes32 jobId0;
        bytes32 jobId1;
    }

    address owner;
    uint256 requestsCount = 0;
    mapping(uint256 => Request) requests;
    mapping(address => bool) memberGuild;
    mapping(bytes32 => bytes32) jobResults;

    address oracle = 0x0bDDCD124709aCBf9BB3F824EbC61C87019888bb;
    bytes32 jobId = "c6a006e4f4844754a6524445acde84a0";
    uint256 fee = 0.01 * 10**18;
    address linkTokenContract = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier onlyMember() {
        require(memberGuild[msg.sender]);
        _;
    }

    constructor() {
        setChainlinkToken(linkTokenContract);
        owner = msg.sender;
    }

    function addMember(address _guild) public onlyOwner {
        memberGuild[_guild] = true;
    }

    function removeMember(address _guild) public onlyOwner {
        delete memberGuild[_guild];
    }

    function createUrl(string memory _lockedLicense, string memory _publicKey)
        internal
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    "https://theunstoppabledev.vercel.app/api/byte32?sourceEncryptedText=",
                    _lockedLicense,
                    "&targetPublicKey=",
                    _publicKey
                )
            );
    }

    function addRequest(string memory _lockedLicense, string memory _publicKey)
        public
        onlyMember
        returns (uint256 requestId)
    {
        string memory url = createUrl(_lockedLicense, _publicKey);
        Chainlink.Request memory request0 = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );
        request0.add("get", url);
        request0.add("path", "p1");

        Chainlink.Request memory request1 = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );
        request1.add("get", url);
        request1.add("path", "p2");

        bytes32 jobId0 = sendChainlinkRequestTo(oracle, request0, fee);
        bytes32 jobId1 = sendChainlinkRequestTo(oracle, request1, fee);

        requests[requestsCount] = Request({
            requestId: requestId,
            jobId0: jobId0, //sendChainlinkRequestTo(oracle, request0, fee);
            jobId1: jobId1 //sendChainlinkRequestTo(oracle, request1, fee);
        });

        // alternative implementation ----------

        jobs[jobId0] = Job({
            requestId: requestsCount,
            guild: msg.sender,
            index: 0,
            pairJobId: jobId1,
            result: bytes32(0)
        });

        jobs[jobId1] = Job({
            requestId: requestsCount,
            guild: msg.sender,
            index: 1,
            pairJobId: jobId0,
            result: bytes32(0)
        });

        // --------------------------------------

        requestsCount++;
        return requestsCount - 1;
    }

    function fulfill(bytes32 _jobId, bytes32 _data)
        public
        recordChainlinkFulfillment(_jobId)
    {
        jobResults[_jobId] = _data;

        // alternative implementation ----------
        if (jobs[jobs[_jobId].pairJobId].result != bytes32(0)) {
            bytes32[2] memory result;
            result[jobs[_jobId].index] = _data;
            result[jobs[jobs[_jobId].pairJobId].index] = jobs[
                jobs[_jobId].pairJobId
            ].result;
            //sent the data to guild
        } else {
            jobs[_jobId].result = _data;
        }
    }

    function getResult(uint256 _requestId)
        external
        view
        onlyMember
        returns (bytes32[2] memory)
    {
        require(jobResults[requests[_requestId].jobId0] != bytes32(0));
        require(jobResults[requests[_requestId].jobId1] != bytes32(0));
        return [
            jobResults[requests[_requestId].jobId1],
            jobResults[requests[_requestId].jobId1]
        ];
    }

    // other supporting functions

    // alternative implementation ----------
    // on the second fulfil of a request pair..
    // ..the result is sent to the oracle

    struct Job {
        uint256 requestId;
        address guild;
        uint256 index; //0 or 1
        bytes32 pairJobId;
        bytes32 result;
    }
    mapping(bytes32 => Job) jobs;

    //--------------------------------------
}
