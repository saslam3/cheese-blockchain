// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import AccessControl from OpenZeppelin
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * Cheese Supply Chain Provenance System:
 * Each cheese wheel is a unique token owned by its current custodian in the supply chain
 * Certificates and raw sensor data stay off-chain (IPFS)
 * Only hashes are stored on-chain
 */

// interface
interface ICheeseProvenance {

    // Stages of supply chain: Produced, Aging, Inspected, Shipped, Delivered
    enum Status {
        Produced,
        Aging,
        Inspected,
        Shipped,
        Delivered
    }

    // Register a new cheese and assign it a unique ID, only used by Producer
    function registerCheese(bytes32 originDataHash) external returns (uint256 id);

    // Move a cheese to its next stage, only used by current custodian
    function updateStatus(uint256 id, Status newStatus) external;

    // Record an inspection result and the IPFS certificate hash, only used by inspector
    function recordInspection(uint256 id, bytes32 certificateHash, bool approved) external;

    // Hand custody to the next party in supply chain, only used by current custodian
    function transferCustody(uint256 id, address to) external;

    // Called by the sensor script to record aging-room data for a cheese, only used by sensor script
    function submitSensorReading(uint256 id, bytes32 readingsHash, bool outOfRange) external;

    // Read a cheese's current custodian and status, anyone can use
    function getCheese(uint256 id) external view returns (address custodian, Status status);
}

// contract
contract CheeseProvenance is ICheeseProvenance, AccessControl {

    // possible roles
    bytes32 public constant PRODUCER_ROLE = keccak256("PRODUCER_ROLE");
    bytes32 public constant AGING_ROLE = keccak256("AGING_ROLE");
    bytes32 public constant INSPECTOR_ROLE = keccak256("INSPECTOR_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant RETAILER_ROLE = keccak256("RETAILER_ROLE");

    // each wheel
    struct Wheel {
        uint256 id;
        address holder;
        Status status;
        uint256 createdAt;
        uint256 updatedAt;
        bytes32 originDataHash;
        bytes32 inspectionHash;
        // inspection result, only meaningful once inspectionHash is set
        bool approved;
    }

    // one entry per step in wheel's history
    struct Record {
        address actor;
        Status status;
        string action;
        uint256 timestamp;
    }

    // wheel count and history
    uint256 public wheelCount;
    mapping(uint256 => Wheel) private wheels;
    mapping(uint256 => Record[]) private history;

    // events for actions on the chain
    event WheelCreated(uint256 indexed id, address indexed producer, bytes32 originDataHash, uint256 timestamp);
    event CustodyTransferred(uint256 indexed id, address indexed from, address indexed to, uint256 timestamp);
    event StatusChanged(uint256 indexed id, Status oldStatus, Status newStatus, address indexed by, uint256 timestamp);
    event InspectionRecorded(uint256 indexed id, address indexed inspector, bytes32 documentHash, bool approved, uint256 timestamp);
    event SensorReadingRecorded(uint256 indexed id, address indexed recorder, bytes32 readingsHash, bool outOfRange, uint256 timestamp);

    // only runs on initial deployment, makes deployer admin
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // producer makes a new wheel and becomes its first holder
    function registerCheese(bytes32 originDataHash) public override returns (uint256)
    {
        // ensure that only producers are registering cheese
        if (!hasRole(PRODUCER_ROLE, msg.sender))
        {
            revert("Only producers can create wheels");
        }

        wheelCount = wheelCount + 1;
        uint256 id = wheelCount;

        wheels[id] = Wheel(id, msg.sender, Status.Produced, block.timestamp, block.timestamp, originDataHash, bytes32(0), false);
        history[id].push(Record(msg.sender, Status.Produced, "Created", block.timestamp));

        emit WheelCreated(id, msg.sender, originDataHash, block.timestamp);
        return id;
    }

    // inspector holding wheel moves it from aging to inspected
    // other statuses are set automatically by transferCustody
    function updateStatus(uint256 id, Status newStatus) public override
    {
        // ensure valid wheel
        if (id == 0 || id > wheelCount)
        {
            revert("Wheel does not exist");
        }

        Wheel storage wheel = wheels[id];

        // ensures only current holder can update
        if (wheel.holder != msg.sender)
        {
            revert("Only the current holder can update status");
        }

        // inspected is the only status that can be set manually
        if (newStatus != Status.Inspected)
        {
            revert("This status cannot be set manually");
        }

        // ensure inspector
        if (!hasRole(INSPECTOR_ROLE, msg.sender))
        {
            revert("Only inspectors can mark a wheel inspected");
        }

        // ensure inspecting aged cheese
        if (wheel.status != Status.Aging)
        {
            revert("Wheel must be aging before inspection");
        }

        // save changes and add to history
        Status oldStatus = wheel.status;
        wheel.status = newStatus;
        wheel.updatedAt = block.timestamp;
        history[id].push(Record(msg.sender, newStatus, "Status updated", block.timestamp));

        // event for changing status
        emit StatusChanged(id, oldStatus, newStatus, msg.sender, block.timestamp);
    }

    // inspector approves or rejects wheel
    function recordInspection(uint256 id, bytes32 certificateHash, bool approved) public override
    {
        // ensure inspector, only they can record inspections
        if (!hasRole(INSPECTOR_ROLE, msg.sender))
        {
            revert("Only inspectors can record inspections");
        }

        // ensure valid wheel
        if (id == 0 || id > wheelCount)
        {
            revert("Wheel does not exist");
        }

        Wheel storage wheel = wheels[id];

        // ensures only current holder(inspector) can inspect
        if (wheel.holder != msg.sender)
        {
            revert("Only the current holder can record inspection");
        }

        // need to be in inspected state
        if (wheel.status != Status.Inspected)
        {
            revert("Wheel must be in Inspected status");
        }

        // only one inspection result per wheel
        if (wheel.inspectionHash != bytes32(0))
        {
            revert("Inspection already recorded");
        }

        // verify hash to check tampering
        if (certificateHash == bytes32(0))
        {
            revert("Document hash is required");
        }

        // save changes and add to history
        // status stays inspected, approved flag decides if it can be shipped
        wheel.inspectionHash = certificateHash;
        wheel.approved = approved;
        wheel.updatedAt = block.timestamp;

        if (approved)
        {
            history[id].push(Record(msg.sender, wheel.status, "Inspection recorded (APPROVED)", block.timestamp));
        }

        else
        {
            history[id].push(Record(msg.sender, wheel.status, "Inspection recorded (REJECTED)", block.timestamp));
        }

        // event for inspection
        emit InspectionRecorded(id, msg.sender, certificateHash, approved, block.timestamp);
    }

    // current holder passes wheel to the next party in the chain
    function transferCustody(uint256 id, address to) public override
    {
        // ensures valid wheel
        if (id == 0 || id > wheelCount)
        {
            revert("Wheel does not exist");
        }

        Wheel storage wheel = wheels[id];

        // ensures only current holder can trasnfer
        if (wheel.holder != msg.sender)
        {
            revert("Only the current holder can transfer");
        }

        Status oldStatus = wheel.status;
        Status newStatus;

        // determine who to transfer custody to based on wheel's current status

        // if produced, send to aging
        if (oldStatus == Status.Produced)
        {
            if (!hasRole(AGING_ROLE, to))
            {
                revert("Recipient must be an aging facility");
            }

            newStatus = Status.Aging;

        }

        // if aging, send to inspector
        else if (oldStatus == Status.Aging)
        {
            if (!hasRole(INSPECTOR_ROLE, to))
            {
                revert("Recipient must be an inspector");
            }

            newStatus = Status.Aging;

        }

        // if inspected and approved, send to distributor
        else if (oldStatus == Status.Inspected)
        {
            if (wheel.inspectionHash == bytes32(0))
            {
                revert("Inspection has not been recorded");
            }

            if (!wheel.approved)
            {
                revert("Wheel was rejected and cannot be shipped");
            }

            if (!hasRole(DISTRIBUTOR_ROLE, to))
            {
                revert("Recipient must be a distributor");
            }

            newStatus = Status.Shipped;

        }

        // if done with distributor, send to retailer
        else if (oldStatus == Status.Shipped)
        {
            if (!hasRole(RETAILER_ROLE, to)) {
                revert("Recipient must be a retailer");
            }

            newStatus = Status.Delivered;

        }

        // if none of those conditions are met, cant transfer wehel
        else
        {
            revert("Wheel cannot be transferred right now");
        }

        // save chagnes and add to chain history
        wheel.holder = to;
        wheel.status = newStatus;
        wheel.updatedAt = block.timestamp;
        history[id].push(Record(to, newStatus, "Custody transferred", block.timestamp));

        // changing custody event
        emit CustodyTransferred(id, msg.sender, to, block.timestamp);

        if (newStatus != oldStatus)
        {
            emit StatusChanged(id, oldStatus, newStatus, msg.sender, block.timestamp);
        }

    }

    // aging facility logs sensor reading for wheel
    function submitSensorReading(uint256 id, bytes32 readingsHash, bool outOfRange) public override
    {
        // ensure aging facility
        if (!hasRole(AGING_ROLE, msg.sender))
        {
            revert("Only aging facilities can record sensor readings");
        }

        // ennsure valid wheel
        if (id == 0 || id > wheelCount)
        {
            revert("Wheel does not exist");
        }

        Wheel storage wheel = wheels[id];

        // ensure only aging facility has wheel
        if (wheel.holder != msg.sender)
        {
            revert("Only the current holder can record sensor readings");
        }

        // ensures wheel is currently aging
        if (wheel.status != Status.Aging)
        {
            revert("Wheel must be aging");
        }

        wheel.updatedAt = block.timestamp;

        // add to history
        // if aging conditions are bad, record that
        if (outOfRange)
        {
            history[id].push(Record(msg.sender, wheel.status, "Sensor reading (OUT OF RANGE)", block.timestamp));
        }

        else
        {
            history[id].push(Record(msg.sender, wheel.status, "Sensor reading", block.timestamp));
        }

        // evnet for sensor reading
        emit SensorReadingRecorded(id, msg.sender, readingsHash, outOfRange, block.timestamp);
    }

    // allows anyone to see who owns a cheese and its status
    function getCheese(uint256 id) public view override returns (address custodian, Status status)
    {
        // ensure valid wheel
        if (id == 0 || id > wheelCount)
        {
            revert("Wheel does not exist");
        }

        Wheel storage wheel = wheels[id];
        return (wheel.holder, wheel.status);
    }

    // allows anyone to see the full state of a wheel
    function getWheel(uint256 id) public view returns (Wheel memory)
    {
        // ensure valid wheel
        if (id == 0 || id > wheelCount)
        {
            revert("Wheel does not exist");
        }

        return wheels[id];
    }

    // allows anyone to see wheel history
    function getHistory(uint256 id) public view returns (Record[] memory)
    {
        // ensure valid wheel
        if (id == 0 || id > wheelCount)
        {
            revert("Wheel does not exist");
        }

        return history[id];
    }

}