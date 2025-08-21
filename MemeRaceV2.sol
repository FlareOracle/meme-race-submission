// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.0/contracts/access/Ownable.sol";
import "https://github.com/flare-foundation/flare-smart-contracts-v2/blob/main/contracts/userInterfaces/LTS/FtsoV2Interface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.0/contracts/token/ERC20/ERC20.sol";

interface IRevShare { 
    function getStakersWithAmounts(uint,uint) external view returns (address[] memory, uint[] memory);
    function totalLocked() external view returns (uint);
    function getStakerCount() external view returns (uint);
}
 

contract PicoMemeRaceV2 is Ownable {

    FtsoV2Interface internal ftsoV2;
    IRevShare internal revsharecontract;

    bytes21[] public feedIds;
    address public admin;

    ERC20 public pico;
    uint public startTime;
    uint public lastRaceFinishTime;
    bool public isRacing = false;
    uint[7] public startPrices;
    uint8[7] public feeddecimals = [10,6,8,11,10,5,6];


    uint[] public racewinners;
    uint public racenumber = 0;
    uint public bettingWindow = 130;
    uint public winningCoin = 0;

    uint public totalWinningBetsFLR;
    uint public totalWinningBetsPico;

    uint public minBetFLR = 5;
    uint public maxBetFLR = 100000;
    uint public minBetPico = 5;
    uint public maxBetPico = 100000;
    uint public admincut = 15;
    uint public affiliatecut = 10;
    uint public forwardcut = 10;
    uint public totalDistFLR;                 
    uint public totalDistPico;
    uint public revshareFLR;                 
    uint public revsharePico;


    uint256 constant PCT_SCALE = 100000000;   


    uint[7] public totalBetsFLR;          
    uint[7] public totalBetsPico;          

    mapping(address => uint[7]) public currentFLRBets;
    mapping(address => uint[7]) public currentPicoBets;

    address[] public activeUsers;
    mapping(address => bool) public isActiveUser;
    mapping(address => uint) public lastwonFLR;
    mapping(address => uint) public lastwonPico;

    mapping(address => address) public forwardaddress;   
    mapping(address => address) public affiliates;

    modifier onlyAdminOrOwner() {
    require(msg.sender == owner() || msg.sender == admin, "No authoriteeh");
    _;
    }

    constructor() Ownable(msg.sender) {  

        //ftsoV2 = FtsoV2Interface(0xB18d3A5e5A85C65cE47f977D7F486B79F99D3d32);
        ftsoV2 = FtsoV2Interface(0x7BDE3Df0624114eDB3A67dFe6753e62f4e7c1d20);
        revsharecontract = IRevShare(0xFF66ee4557fB3DE843FA978D8EF08cEe0674fbF2);  ///////NEW REV SHARE

        feedIds.push(bytes21(0x01424f4e4b2f555344000000000000000000000000)); // bonk
        feedIds.push(bytes21(0x01444f47452f555344000000000000000000000000)); // doge
        feedIds.push(bytes21(0x0150454e47552f5553440000000000000000000000)); // pengu
        feedIds.push(bytes21(0x01504550452f555344000000000000000000000000)); // pepe
        feedIds.push(bytes21(0x01534849422f555344000000000000000000000000)); // shib
        feedIds.push(bytes21(0x015452554d502f5553440000000000000000000000)); // trump
        feedIds.push(bytes21(0x015749462f55534400000000000000000000000000)); // wif
      
        admin = 0xCe1E4534d08db70E0f897395296199492Bd8A8EB;
        setCurrency(0x5Ef135F575d215AE5A09E7B30885E866db138aF6);

    }

//OWNER SETTERS

    function setFTSO(address _ftsoV2) external onlyOwner {
        ftsoV2 = FtsoV2Interface(_ftsoV2);
    }

    function setRevShare(address _add) external onlyOwner {
        revsharecontract = IRevShare(_add);
    } 

    function setAdmin(address _add) external onlyOwner {
        admin = _add;
    }

    function setBettingWindow(uint _bettingWindow) external onlyOwner {
        bettingWindow = _bettingWindow;
    }

    function setCuts(uint _cut, uint _affilcut, uint _forwardcut) external onlyAdminOrOwner  {
        admincut = _cut;
        affiliatecut = _affilcut;
        forwardcut = _forwardcut;
    }


    function setBetRange(uint _minBetFLR, uint _maxBetFLR,uint _minBetpico, uint _maxBetpico) external onlyOwner {
        require(_minBetFLR < _maxBetFLR && _minBetpico < _maxBetpico, "Invalid bet range");

        minBetFLR = _minBetFLR;
        maxBetFLR = _maxBetFLR;
        minBetPico = _minBetpico;
        maxBetPico = _maxBetpico;
    }

    function setCurrency(address _token) public onlyOwner {
        pico = ERC20(_token);
    }

    function setAffiliateOverride(address _who, address _affaddress) external onlyOwner {
        affiliates[_who] = _affaddress;
    }

//Affiliates

    function setAffiliate(address _affaddress) public {

        require(affiliates[msg.sender] == address(0), "Already Set in stone");
        require(msg.sender != _affaddress, "Cant refer yourself");
        
        if(_affaddress== address(0)){
            affiliates[msg.sender] = admin;
        }
        else{
            affiliates[msg.sender] = _affaddress;
        }
                
    }
// Placing a bet

    function placeBetsFLR(uint256[] memory whichCoins) public payable {
        uint256 count = whichCoins.length;
        require(count > 0 && count <= 7, "Invalid number of bets");
        require(block.timestamp - startTime < bettingWindow, "Betting time is over");
        require(msg.value % count == 0, "Bet not divisible equally");

        if(affiliates[msg.sender] == address(0)){
            affiliates[msg.sender] = admin;
        }

        uint256 share = msg.value / count;
        require(share >= minBetFLR * 1e18 && share <= maxBetFLR * 1e18, "Invalid per-coin bet amount" );

        // First-time bettor bookkeeping
        if (!isActiveUser[msg.sender]) {
            activeUsers.push(msg.sender);
            isActiveUser[msg.sender] = true;
        }

        for (uint256 i = 0; i < count; i++) {
            uint256 coin = whichCoins[i];
            require(coin < feedIds.length, "Invalid coin index");
            require(
                currentFLRBets[msg.sender][coin] == 0,
                "Already bet on this coin"
            );

            currentFLRBets[msg.sender][coin] = share;
            totalBetsFLR[coin] += share;
        }
    }


    function placeBetsPico(uint256[] memory whichCoins, uint256 totalPicoAmount) public {
        
        uint256 count = whichCoins.length;
        require(count > 0 && count <= 7, "Invalid number of bets");
        uint256 totalWei = totalPicoAmount * 1e18;
        uint256 shareWei = totalWei / count;
        require(shareWei * count == totalWei, "Unequal total split");
        require(shareWei >= (minBetPico * 1e18) && shareWei <= (maxBetPico * 1e18), "Invalid per-coin amount");
        require(block.timestamp - startTime < bettingWindow, "Betting is over");

        if(affiliates[msg.sender] == address(0)){
            affiliates[msg.sender] = admin;
        }

        pico.transferFrom(msg.sender, address(this), totalWei);

        // First‐time bettor bookkeeping
        if (!isActiveUser[msg.sender]) {
            activeUsers.push(msg.sender);
            isActiveUser[msg.sender] = true;
        }

        for (uint256 i = 0; i < count; i++) {
            uint256 coin = whichCoins[i];
            require(coin < feedIds.length,              "Invalid coin index");
            require(
                currentPicoBets[msg.sender][coin] == 0,
                "Already bet on this coin"
            );

            currentPicoBets[msg.sender][coin] = shareWei;
            totalBetsPico[coin] += shareWei;
        }
    }

    function betOnAllFLR() public payable {
        require(msg.value % 7 == 0, "Bet not divisible equally");
        uint[] memory coins = new uint[](7);
        
        for (uint256 i = 0; i < 7; i++) {
            coins[i] = i;
        }
        placeBetsFLR(coins);
    }

    function betOnAllPico(uint256 picoAmount) public {
        require((picoAmount * 1e18) % 7 == 0, "Bet not divisible equally");
        uint[] memory coins = new uint[](7);
        
        for (uint256 i = 0; i < 7; i++) {
            coins[i] = i;
        }
        placeBetsPico(coins, picoAmount);
    }

//Set Forward address 
    function setForwardingAddress(address _forward) external {
        forwardaddress[msg.sender] = _forward;
    }

// FINISH / PAYOUT / START AGAIN

    function determinewinningCoin() external payable onlyAdminOrOwner {

        uint256 n = feedIds.length;

        (uint256 feed0,,) = ftsoV2.getFeedById{ value: 0 }(feedIds[0]);
        int256 maxChange = _computeChangeBP(startPrices[0], feed0);
        uint256 maxIdx = 0;

        for (uint256 i = 1; i < n; i++) {
            (uint256 feedVal,,) = ftsoV2.getFeedById{ value: 0 }(feedIds[i]);
            int256 change = _computeChangeBP(startPrices[i], feedVal);
            if (change > maxChange) {
                maxChange = change;
                maxIdx = i;
            }
        }

        winningCoin = maxIdx;
        racewinners.push(winningCoin);
        racenumber++;

        totalWinningBetsFLR = 0;
        totalWinningBetsPico = 0;

        isRacing = false;
        lastRaceFinishTime = block.timestamp;

        totalWinningBetsFLR  = totalBetsFLR[winningCoin];
        totalWinningBetsPico = totalBetsPico[winningCoin];

    }


    function payoutAdmin() external onlyAdminOrOwner {

        uint256 flrBal = address(this).balance;
        uint256 flrCut = (flrBal * admincut) / 1000;
        payable(admin).transfer(flrCut);

        uint256 picoBal = pico.balanceOf(address(this));
        uint256 picoCut = (picoBal * admincut) / 1000;
        pico.transfer(admin, picoCut);

    }


    function payoutStakeHolders(uint256 start, uint256 count) external onlyAdminOrOwner {

        if (start == 0) {
            revshareFLR  = address(this).balance   / 100;  // in wei
            revsharePico = pico.balanceOf(address(this)) / 100;  // in pico‑wei
        }

        (address[] memory stakers, uint256[] memory lockedAmounts) = revsharecontract.getStakersWithAmounts(start, count);

        uint256 totalStaked = revsharecontract.totalLocked();  // whole‑unit sum

        for (uint256 i = 0; i < stakers.length; i++) {
            uint256 stake = lockedAmounts[i];
            if (stake == 0 || totalStaked == 0) continue;

            uint256 flrShare  = (revshareFLR  * stake) / totalStaked;
            uint256 picoShare = (revsharePico * stake) / totalStaked;

            if (flrShare > 0) {
                (bool okUser, ) = stakers[i].call{ value: flrShare }("");
                require(okUser, "Payout transfer failed");
            }
            if (picoShare > 0) {
                pico.transfer(stakers[i], picoShare);
            }
        }
    }





    function payoutWinnersFLRBatch(uint256 start, uint256 count) external onlyAdminOrOwner {

        uint256 n = activeUsers.length;
        require(start < n, "Start OOB");

        if (start == 0) {
            uint256 rem = address(this).balance;            
            totalDistFLR = (rem * 99) / 100;                
        }
        uint256 end = start + count > n ? n : start + count;

        for (uint256 i = start; i < end; i++) {
        
            address payable user = payable(activeUsers[i]);
            uint256 bet = currentFLRBets[user][winningCoin];
            lastwonFLR[user] = 0;

            if (bet > 0) {

                uint256 totalpay = (bet * totalDistFLR) / totalWinningBetsFLR;

                address payable affiliate = payable(affiliates[user]);
                uint thecut = (totalpay * affiliatecut) / 1000;
                uint pay = totalpay - thecut;

                (bool okAffil, ) = affiliate.call{value: thecut}("");
                require(okAffil, "Affil Xfer Fail");

                address payable fwd = payable(forwardaddress[user]);
                
                if (fwd != address(0)) {
                   
                    uint256 fee = (pay * forwardcut) / 1000;
                    uint256 userShare = pay - fee;

                    (bool okAdmin, ) = admin.call{ value: fee }("");
                    require(okAdmin, "Admin fee transfer failed");

                    (bool okUser, ) = fwd.call{ value: userShare }("");
                    require(okUser, "Payout transfer failed");

                    lastwonFLR[user] = userShare;


                } else {

                    (bool success, ) = user.call{value: pay}("");
                    require(success, "Payout Xfer Fail");
                    lastwonFLR[user] = pay;
                }


            }        
        
        }


    }

    function payoutWinnersPicoBatch(uint256 start, uint256 count) external onlyAdminOrOwner {

        uint256 n = activeUsers.length;
        require(start < n, "Start OOB");

        if (start == 0) {
            uint256 rem = pico.balanceOf(address(this));  
            totalDistPico = (rem * 99) / 100;
        }
        uint256 end = start + count > n ? n : start + count;

        for (uint256 i = start; i < end; i++) {
            address user = activeUsers[i];
            uint256 bet = currentPicoBets[user][winningCoin];
            lastwonPico[user] = 0;

            if (bet > 0) {

                uint256 totalpay = (bet * totalDistPico) / totalWinningBetsPico;
                address fwd = forwardaddress[user];
                
                uint thecut = (totalpay * affiliatecut) / 1000;
                uint pay = totalpay - thecut;
                
                pico.transfer(affiliates[user],thecut);
                        
                if (fwd != address(0)) {
                    uint256 fee = (pay * forwardcut) / 1000;
                    uint256 userShare = pay - fee;

                    pico.transfer(admin, fee);
                    pico.transfer(user, userShare);

                    lastwonPico[user] = userShare;
                } else {
                    pico.transfer(user, pay);
                    lastwonPico[user] = pay;
                }           
            
            
            }
        }

    }


    function clearActiveUsersBatch(uint256 batchSize) public onlyAdminOrOwner {
        
        uint256 len = activeUsers.length;
        require(len > 0, "No active users to clear");

        // we only clear as many as we have
        uint256 toClear = batchSize < len ? batchSize : len;
        for (uint256 i = 0; i < toClear; i++) {

            address user = activeUsers[len - 1 - i];
            delete currentFLRBets[user];
            delete currentPicoBets[user];
            isActiveUser[user] = false;
            activeUsers.pop();
        }
    }


    function startRace() external payable onlyAdminOrOwner{
        
        // Reset state for a new race
        for (uint i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            delete currentFLRBets[user];
            delete currentPicoBets[user];
            isActiveUser[user] = false;
        }
        
        delete activeUsers;
        delete totalBetsFLR;
        delete totalBetsPico;

        startTime = block.timestamp;
        isRacing = true;

        // Set start prices for all feeds
        for (uint i = 0; i < feedIds.length; i++) {
            (uint feedValue,int8 decSigned,) = ftsoV2.getFeedById{ value: 0 }(feedIds[i]);
            startPrices[i] = feedValue;
            feeddecimals[i] = uint8(decSigned);
        }
    }


//VIEWERS


    function getAllPrices() external payable returns (string[] memory) {
        string[] memory prices = new string[](feedIds.length);
        for (uint i = 0; i < feedIds.length; i++) {

            (uint feedValue, int8 decimals,) = ftsoV2.getFeedById{ value: 0 }(feedIds[i]);
            prices[i] = formatPriceWithDecimals(feedValue, decimals);
        }
        return prices;
    }

    function getAllStartPrices() external view returns (string[] memory) {
        string[] memory prices = new string[](feedIds.length);
        for (uint i = 0; i < feedIds.length; i++) {
            prices[i] = formatPriceWithDecimals(startPrices[i],int8(feeddecimals[i]));
           
        }
        return prices;
    }

    function getCurrentPercentChanges() external payable returns (int256[] memory) {
         
        uint256 n = feedIds.length;
        int256[] memory changes = new int256[](n);
        for (uint256 i = 0; i < n; i++) {
            (uint256 nowPrice,,) = ftsoV2.getFeedById{ value: 0 }(feedIds[i]);
            changes[i] = _computeChangeBP(startPrices[i], nowPrice);
        }
        return changes;

    }


    function getCurrentFLRBets(address user) public  view returns (uint[7] memory) {

        return currentFLRBets[user];
    }

    function getCurrentPicoBets(address user) public view returns (uint[7] memory) {

        return currentPicoBets[user];
    }

    function getMyStats(address user) public view returns (uint[7] memory flrbets,uint[7] memory picobets,uint lastflr,uint lastpico){
        return(getCurrentFLRBets(user),getCurrentPicoBets(user),lastwonFLR[user],lastwonPico[user]);
    }


    function getPrizePools() external view returns(uint flrprize, uint picoprize){
        return (address(this).balance,pico.balanceOf(address(this)));
    }

    function getBettingLive() public view returns(bool islive){
        return(block.timestamp - startTime < bettingWindow);
    }

    function getRacingSeconds() public view returns(uint secondsracing){
        return(block.timestamp - startTime);
    }

    function getUserLength() external view returns(uint usercount){
        return activeUsers.length;
    }

    function getAllStats() external view returns(
        bool isracing,
        bool isbettinglive,
        uint usercount,
        uint racingseconds,
        uint betwindow,
        uint flrprize,
        uint picoprize,
        uint lastwinner,
        uint[7] memory bettotalsFLR,
        uint[7] memory bettotalsPICO

    ){

        return(isRacing, getBettingLive(), activeUsers.length, getRacingSeconds(), bettingWindow, address(this).balance,pico.balanceOf(address(this)), winningCoin,totalBetsFLR,totalBetsPico);
    }

    function getActivePlayers(uint start, uint count) external view returns (address[] memory players, uint[] memory bettotalsFLR, uint[] memory bettotalsPico) {
        
        uint totalbetters = activeUsers.length;
        require(start < totalbetters, "Start index OOB");

        if (start + count > totalbetters) {
            count = totalbetters - start;
        }

        address[] memory resultPlayers = new address[](count);
        uint[] memory resultBetsFLR = new uint[](count);
        uint[] memory resultBetsPico = new uint[](count);

        for (uint i = 0; i < count; i++) {
            
            address player = activeUsers[start + i];

            uint256 totalFlr;
            uint256 totalPico;
                
            for (uint256 j = 0; j < 7; j++) {
                totalFlr  += currentFLRBets[player][j];
                totalPico += currentPicoBets[player][j];
            }

            resultPlayers[i] = player;
            resultBetsFLR[i] = totalFlr;
            resultBetsPico[i] = totalPico;

        }

        return (resultPlayers, resultBetsFLR,resultBetsPico);

    }
    
//Helpers
    function formatPriceWithDecimals(uint price, int8 decimals) internal pure returns (string memory) {
        if (decimals >= 0) {
            uint decimalPlaces = uint(int256(decimals));
            uint integerPart = price / (10 ** decimalPlaces);
            uint fractionalPart = price % (10 ** decimalPlaces);
            return string(abi.encodePacked(uintToString(integerPart), ".", fractionalToString(fractionalPart, decimalPlaces)));
        } else {
            uint adjustedPrice = price * (10 ** uint(-int256(decimals)));
            return uintToString(adjustedPrice);
        }
    }

    function fractionalToString(uint fractionalPart, uint decimals) internal pure returns (string memory) {
        bytes memory buffer = new bytes(decimals);
        for (uint i = decimals; i > 0; i--) {
            buffer[i - 1] = bytes1(uint8(48 + fractionalPart % 10));
            fractionalPart /= 10;
        }
        return string(buffer);
    }

    function uintToString(uint value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint temp = value;
        uint digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }


    function _computeChangeBP(uint256 startPrice, uint256 endPrice) private pure returns (int256) {
 
        uint256 diff;
        if (endPrice >= startPrice) {
            diff = endPrice - startPrice;
            return int256((diff * PCT_SCALE) / startPrice);
        } else {
            diff = startPrice - endPrice;
            return -int256((diff * PCT_SCALE) / startPrice);
        }
    }

//FAILSAFES

    function collectFees() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    function collectAllTokens(address _token) external onlyOwner {
        ERC20 token = ERC20(_token);
        uint balance = token.balanceOf(address(this));
        token.transfer(owner(), balance);
    }

//FIN
}
