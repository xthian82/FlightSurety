
var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');
const Web3 = require('web3');

contract('Flight Surety Tests', async (accounts) => {

  var config;
  var fund;
  var flight;
  var insurance;
  var web3;
  var passenger;

  before('setup contract', async () => {
    config = await Test.Config(accounts);
    fund = Web3.utils.toWei('10', "ether");
    insurance = Web3.utils.toWei('1', "ether");
    flight = 'OLY 1902';
    web3 = new Web3(config.url);
    passenger = accounts[7];
    await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
  });

  /****************************************************************************************/
  /* Operations and Settings                                                              */
  /****************************************************************************************/

  it(`(multiparty) has correct initial isOperational() value`, async function () {

    // Get operating status
    let status = await config.flightSuretyData.isOperational.call();
    assert.equal(status, true, "Incorrect initial operating status value");

  });

  it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

      // Ensure that access is denied for non-Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, true, "Access not restricted to Contract Owner");
            
  });

  it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

      // Ensure that access is allowed for Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyData.setOperatingStatus(false);
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, false, "Access not restricted to Contract Owner");
      
  });

  it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

      await config.flightSuretyData.setOperatingStatus(false);

      let reverted = false;
      try 
      {
          await config.flightSurety.setTestingMode(true);
      }
      catch(e) {
          reverted = true;
      }
      assert.equal(reverted, true, "Access not blocked for requireIsOperational");      

      // Set it back for other tests to work
      await config.flightSuretyData.setOperatingStatus(true);

  });

  it('(airline) cannot register an Airline using registerAirline() if it is not funded', async () => {
    
    // ARRANGE
    let newAirline = accounts[2];

    // ACT
    try {
        await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});
    }
    catch(e) {

    }
    let result = await config.flightSuretyData.isAirline.call(newAirline); 

    // ASSERT
    assert.equal(result, false, "Airline should not be able to register another airline if it hasn't provided funding");

  });


  // -----------
  it("(airline) first registered when contract is deployed", async () => {

    // ACT
    const isRegistered = await config.flightSuretyData.isAirline.call(config.firstAirline);

    // ASSERT
    assert.equal(isRegistered, true, "First airline add failed");
  });


  it("(airline) can register another airline", async () => {

    // ARRANGE
    let newAirline = accounts[2];

    try {
        // ACT
        config.flightSuretyApp.registerAirline(newAirline, { from: config.firstAirline, value: fund, gasPrice: 0});
    } catch(e) {}

    // ASSERT
    const isRegistered = await config.flightSuretyData.isAirline.call(newAirline);
    assert.equal(isRegistered, true, "Registration of 2nd airline failed");
  });

  xit('(airline) adding more than 4 airlines needs 50% reigstered airlines consensus', async () => {

    // ARRANGE
    const thirdAirline = accounts[3];
    const fourthAirline = accounts[4];
    const fifthAirline = accounts[5];


    await config.flightSuretyApp.registerAirline(thirdAirline, {from: accounts[2], value: fund, gasPrice: 0});
    await config.flightSuretyApp.registerAirline(fourthAirline, {from: accounts[2], value: fund, gasPrice: 0});

    // after fifth airline, needs consensus
    await config.flightSuretyApp.registerAirline(fifthAirline, {from: accounts[2], value: fund, gasPrice: 0});
    let isRegistered = await config.flightSuretyData.isAirline.call(fifthAirline);

    // ASSERT
    assert.equal(isRegistered, false, "Airline should not be registered until multiconsesus has reached");

    await config.flightSuretyApp.registerAirline(fifthAirline, {from: thirdAirline, value: fund, gasPrice: 0});
    isRegistered = await config.flightSuretyData.isAirline.call(fifthAirline);
    assert.equal(isRegistered, true, "Airline should be registered as multiconsesus has reached");
  });

  it('(flights) can be registered and retrieved', async () => {

    const timestamp = Math.floor(Date.now() / 1000);
    var error = false;

    try {
        await config.flightSuretyApp.registerFlight.call(config.firstAirline, flight, timestamp);
    }
    catch(e) {
        error = true;
    }

    assert.equal(error, false, "Flights should be allowed to be registerd by participating airlines")

    const oracleEvent = await config.flightSuretyApp.fetchFlightStatus(config.firstAirline, flight, timestamp);
    assert.equal(oracleEvent.logs[0].event, 'OracleRequest', 'OracleRequest event failed');

  });

  it('(passenger) buy insurance up to 1 ether', async () => {

    var balancePreTransaction = await web3.eth.getBalance(passenger);
    console.log(`(buyInsurance) **** Balance before credit => ${balancePreTransaction}`);

      try {
        await config.flightSuretyApp.buyInsurance(config.firstAirline, flight, {from : passenger, value: insurance, gasPrice: 0});
    } catch(e){
        console.log("on buyInsurance");
        console.log(e);
    }

    const balancePostTransaction = await web3.eth.getBalance(passenger);
      console.log(`(buyInsurance) **** Balance after credit => ${balancePostTransaction}`);


      assert.equal(insurance, balancePreTransaction - balancePostTransaction, 'no insurance deducted');
  });

  it('(passenger) should be able to be refunded', async () => {

  const balancePreTransaction = await web3.eth.getBalance(passenger);
 console.log(`(fundInsurance) **** Balance before credit => ${balancePreTransaction}`);
    try {
        await config.flightSuretyData.creditInsurees(config.firstAirline, flight);
    } catch (e) {
        console.log("on creditInsurees !!!");
        console.log(e);
    }

    const withdrawAmount = insurance * 1.5;


      try {
          await config.flightSuretyApp.fundInsurance({from: passenger, value: web3.utils.toWei('30', 'ether'), gasPrice: 0});

      } catch(e){
          console.log("on fundInsurance !!!");
          console.log(e);
      }
    const balancePostTransaction = await web3.eth.getBalance(passenger);
      console.log(`(fundInsurance) **** Balance after credit => ${balancePostTransaction}`);
    assert.equal(balancePostTransaction - balancePreTransaction, withdrawAmount, 'Incorrect amount funded in transaction');
  });
});
