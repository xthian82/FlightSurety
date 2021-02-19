pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/
    bool private operational = true;
    address private contractOwner;                                      // Account used to deploy contract

    // Flight status codes
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    uint8 constant private CREDIT_MULTIPLIER = 15;
    uint8 constant private CREDIT_DIVIDER = 10;
    uint256 private constant MIN_INSURANCE_AMOUNT = 1 ether;

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        string flightName;
        uint256 updatedTimestamp;
        address airline;
    }

    struct Insurance {
        address passenger;
        uint256 amount;
    }

    mapping(bytes32 => Flight) private flights;
    mapping(address => uint256) private airlines;
    mapping(bytes32 => Insurance[]) private flightInsurances;
    mapping(address => uint256) passengerInsurances;
    mapping(address => bool) private authorisedCallers;


    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor(address airlineAddress) public {
        contractOwner = msg.sender;
        airlines[airlineAddress] = 1;
        authorisedCallers[msg.sender] = true;
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational()
    {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireAirlineRegistered(address airline)
    {
        require(airlines[airline] == 1, "Airline is not registered");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */
    function isOperational() external view returns(bool)
    {
        return operational;
    }

    /**
    * Add an authorised caller.
    * Can only be called from FlightSuretyApp contract
    */
    function authorizeCaller(address caller) external requireContractOwner {
        authorisedCallers[caller] = true;
    }

    /**
    * Disable authorised caller.
    * Can only be called from FlightSuretyApp contract
    */
    function deauthorizeCaller(address caller) external requireContractOwner {
        authorisedCallers[caller] = false;
    }

    function isAirline(address airline) external view returns(bool) {
        return airlines[airline] == 1;
    }

    function isLateFlight(uint8 statusCode) external pure returns(bool) {
        return statusCode == STATUS_CODE_LATE_AIRLINE;
    }

    function owner() public view returns(address) {
        return contractOwner;
    }


    function updateFlightStatus(address airline,
                                string memory flight,
                                uint256 timestamp,
                                uint8 statusCode)
                                requireAirlineRegistered(airline)
                                public {
        bytes32 key = getFlightKey(airline, flight, timestamp);

        require(flights[key].isRegistered, "Flight not registered");
        require(flights[key].airline == airline, "Only flight owning airline can change a flights status");

        flights[key].statusCode = statusCode;
        flights[key].updatedTimestamp = timestamp;
    }

    function registerFlight(address airline, string flightName, uint256 timestamp) external requireIsOperational {
        bytes32 flightKey = getFlightKey(airline, flightName, timestamp);
        flights[flightKey].flightName = flightName;
        flights[flightKey].airline = airline;
        flights[flightKey].statusCode = STATUS_CODE_UNKNOWN;
        flights[flightKey].updatedTimestamp = timestamp;
        flights[flightKey].isRegistered = true;
    }

    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */
    function setOperatingStatus
                            (
                                bool mode
                            )
                            external
                            requireContractOwner
    {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function registerAirline(address airline) external requireIsOperational
    {
        require(airline != address(0), "'airline' must be a valid address.");

        airlines[airline] = 1;
    }


   /**
    * @dev Buy insurance for a flight
    *
    */
    function buy(address passenger, uint256 amount, address airline, string flight) external payable requireIsOperational
    {
        bytes32 key = getInsuranceKey(airline, flight);
        Insurance memory insurance = Insurance({ passenger: passenger, amount: amount });
        flightInsurances[key].push(insurance);
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees(address airline, string flight) external payable requireIsOperational
    {
        bytes32 insuranceKey = getInsuranceKey(airline, flight);
        Insurance[] memory passengersToPay = flightInsurances[insuranceKey];

        for (uint ii=0; ii < passengersToPay.length; ii++) {
            pay(passengersToPay[ii].passenger, passengersToPay[ii].amount);
        }

        delete flightInsurances[insuranceKey];
    }


    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay(address passenger, uint256 amount) internal
    {
        require(amount > 0, "amount not valid for credit");

        uint256 currentBalance = passengerInsurances[passenger];
        uint256 toPay = amount.mul(CREDIT_MULTIPLIER).div(CREDIT_DIVIDER);

        passengerInsurances[passenger] = currentBalance.add(toPay);
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */
    function fund(address passenger) external payable
    {
        uint256 transferAmount = passengerInsurances[passenger];
        require(transferAmount > 0, "No withdrawable amount available");
        passengerInsurances[passenger] = 0;
        passenger.transfer(transferAmount);
    }

    function getFlightKey
                        (
                            address airline,
                            string memory flight,
                            uint256 timestamp
                        )
                        internal view requireIsOperational
                        returns(bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    function getInsuranceKey(address airline, string memory flight) internal view requireIsOperational returns(bytes32) {
        return keccak256(abi.encodePacked(airline, flight));
    }

    function ()
    payable
    external
    {
    }
}
