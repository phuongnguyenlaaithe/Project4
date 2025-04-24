// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";


contract TokenExchange is Ownable {
    string public exchange_name = 'Titan_Exchange'; 

    // TODO: paste token contract address here
    // e.g. tokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3
    address tokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;                                  // TODO: paste token contract address here
    Token public token = Token(tokenAddr);                                

    // Liquidity pool for the exchange
    uint private token_reserves = 0;
    uint private eth_reserves = 0;

    // Fee Pools
    uint private token_fee_reserves = 0;
    uint private eth_fee_reserves = 0;

    // Liquidity pool shares:
    // phân số sở hữu: mỗi LP sẽ sở hữu 1 phân số f của 'mining pool'. phân số được lưu trữ
    // trong smart contract cho mỗi LP (thông qua mapping có tên lps lưu trữ số lượng cổ phần của mỗi địa chỉ)
    mapping(address => uint) private lps;

    // Allow to store the address of liquidity providers
    // For Extra Credit only: to loop through the keys of the lps mapping
    address[] private lp_providers;      

    // Total Pool Shares
    uint private total_shares = 0;

    // liquidity rewards: take 3% from each swap 
    uint private swap_fee_numerator = 3;                
    uint private swap_fee_denominator = 100;

    // Constant: x * y = k
    uint private k;

    // Handle precision
    uint private multiplier = 10**5;

    constructor() {}
    

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        onlyOwner
    {
        // This function is already implemented for you; no changes needed.

        // require pool does not yet exist:
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need eth to create pool.");
        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to create the pool");
        require (amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this)); // take token balance of contract token
        eth_reserves = msg.value;
        k = token_reserves * eth_reserves;

        // Pool shares set to a large value to minimize round-off errors
        total_shares = 10**5;
        // Pool creator has some low amount of shares to allow autograder to run -> trach how much 'ownership' they have in the pool by usin shares
        lps[msg.sender] = 100; // start with 100 pool shares to owner (?owner have 100% shares in this liquidity pool)
    }

    // For use for ExtraCredit ONLY
    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    // lp_providers: a list of providers
    function removeLP(uint index) private {
        require(index < lp_providers.length, "specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Phí giao dịch: phí swap được đạt là 3% (được biểu diễn bơir 'swap fee numerator' và 'swap fee denominator')
    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint, uint) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    // Function getReserves
    function getReserves() public view returns (uint, uint) {
        return (eth_reserves, token_reserves);
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================
    
    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    /** CÁCH HOẠT ĐỘNG CỦA addLiquidity()
     * c1: Gửi ETH: người dùng gọi hàm với ETH kèm theo (msg.value)
     * c2: Tính số token cần nạp: -> giữ tỷ lệ x/y không đổi
     *    + Dựa vào tỷ lệ hiện tại trong pool để tính số tokenken cần tương ứng
     * c3: Kiểm tra và chuyển token:
     *    + Nếu người dùng có đủ token và cho phép contract chuyển (approve()) -> contract sẽ gọi transferFrom() để lấy 1000 toekn từ người dùng
          + Nếu không đủ -> giao dịch fails
     * c4: cập nhật trạng thái
     *    + ETH và token trong pool tăng lên
          + Ghi nhận người dùng này vừa đống bao nhiêu thanh khoản
     */
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
    external 
    payable
    {
        uint amountETH = msg.value;
        require(amountETH > 0, "ETH amount must be greater than 0");
        require(eth_reserves > 0 && token_reserves > 0, "Insufficient liquidity in the pool");

        uint amountTokens = (amountETH * token_reserves) / eth_reserves;
        require(token.balanceOf(msg.sender) >= amountTokens, "Insufficient token balance");

        // Calculate the current exchange rate before transferring tokens
        uint current_exchange_rate = (eth_reserves * multiplier / 10**18) / token_reserves;
        console.log("eth_reserves:", eth_reserves);
        console.log("token_reserves:", token_reserves);
        console.log("Current Exchange Rate:", current_exchange_rate);
        require(current_exchange_rate <= max_exchange_rate, "Slippage too high");
        require(current_exchange_rate >= min_exchange_rate, "Slippage too low");


        uint shares_to_mint = (amountETH * total_shares) / eth_reserves;
        require(shares_to_mint > 0, "Zero LP shares");

        if (lps[msg.sender] == 0) {
            lp_providers.push(msg.sender);
        }
        lps[msg.sender] += shares_to_mint;
        total_shares += shares_to_mint;
        // update pool state
        eth_reserves += amountETH;
        token_reserves += amountTokens;
        // Transfer tokens after slippage checks
        token.transferFrom(msg.sender, address(this), amountTokens);
    }



    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove:
    /*
     * Calculate their portion of tokens/ETH based on shares
     * Transfer back to user
     * Update reserves and shares
     */
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH, uint max_exchange_rate, uint min_exchange_rate)
        public 
        payable
    {
        uint userShares = lps[msg.sender];
        require(userShares > 0, "Not a liquidity provider");

        // Calculate the user's proportional share of ETH reserves
        uint maxETHWithdrawable = (userShares * eth_reserves) / total_shares;
        require(amountETH <= maxETHWithdrawable, "Trying to withdraw more than owned");

        // Calculate shares to burn
        uint shares_to_burn = (amountETH * total_shares) / eth_reserves;
        require(shares_to_burn > 0, "Not enough shares");

        // Compute the amount of tokens to withdraw
        uint amountTokens = (shares_to_burn * token_reserves) / total_shares;

        require(eth_reserves - amountETH > 0, "Cannot empty ETH reserves");
        require(token_reserves - amountTokens > 0, "Cannot empty token reserves");

        // Calculate the exchange rate after removing liquidity
        uint current_exchange_rate = (eth_reserves * multiplier / 10**18) / token_reserves;
        console.log("Current Exchange Rate:", current_exchange_rate);
        console.log("Max Exchange Rate:", max_exchange_rate);
        console.log("Min Exchange Rate:", min_exchange_rate);
        require(current_exchange_rate <= max_exchange_rate, "Slippage too high");
        require(current_exchange_rate >= min_exchange_rate, "Slippage too low");
        // Calculate LP rewards from fee reserves
        uint rewardEth = (shares_to_burn * eth_fee_reserves) / total_shares;
        uint rewardTokens = (shares_to_burn * token_fee_reserves) / total_shares;

        // Update state
        lps[msg.sender] -= shares_to_burn;
        total_shares -= shares_to_burn;
        eth_fee_reserves -= rewardEth;
        token_fee_reserves -= rewardTokens;


        // Remove user from LP providers list if they have no remaining shares
        if (lps[msg.sender] == 0) {
            for (uint i = 0; i < lp_providers.length; i++) {
                if (lp_providers[i] == msg.sender) {
                    removeLP(i);
                    break;
                }
            }
        }
        eth_reserves -= amountETH;
        token_reserves -= amountTokens;

        // Transfer ETH and Tokens to the user
        // payable(msg.sender).transfer(amountETH + rewardEth);
        // token.transfer(msg.sender, amountTokens + rewardTokens);
        payable(msg.sender).transfer(amountETH);
        token.transfer(msg.sender, amountTokens);
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(uint max_exchange_rate, uint min_exchange_rate)
        external
        payable
    {
        /******* TODO: Implement this function *******/
        uint userShares = lps[msg.sender];
        console.log("userShares:", userShares);
        
        require(userShares > 0, "Not a liquidity provider");

        uint amountETH = (userShares * eth_reserves) / total_shares;
        uint amountTokens = (userShares * token_reserves) / total_shares;

        require(eth_reserves > amountETH, "Insufficient ETH reserves");
        require(token_reserves > amountTokens, "Insufficient Tokens reserves");


        // Calculate the exchange rate
        uint current_exchange_rate = (eth_reserves  * multiplier / 10 ** 18) / token_reserves;

        require(current_exchange_rate <= max_exchange_rate, "Slippage: Exchange rate too high");
        require(current_exchange_rate >= min_exchange_rate, "Slippage: Exchange rate too low");

        // Calculate LP rewards from fee reserves
        uint rewardEth = (userShares * eth_fee_reserves) / total_shares;
        uint rewardTokens = (userShares * token_fee_reserves) / total_shares;

        // Update state
        lps[msg.sender] = 0;
        total_shares -= userShares;
        eth_fee_reserves -= rewardEth;
        token_fee_reserves -= rewardTokens;
        
        // Remove LP 
        for (uint i = 0; i < lp_providers.length; i++){
            if (lp_providers[i] == msg.sender){
                removeLP(i);
                break;
            }
        }
        
        eth_reserves -= amountETH;
        token_reserves -= amountTokens;
        // transfer
        // payable(msg.sender).transfer(amountETH + rewardEth);
        // token.transfer(msg.sender, amountTokens + rewardTokens);
        payable(msg.sender).transfer(amountETH);
        token.transfer(msg.sender, amountTokens);

    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH:
    /*
     * Transfer tokens in 
     * apply formula to give ETH out
     * take 3% fee
     */
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate)
        external 
        payable
    {   

        require(amountTokens > 0, "amountTokens must be greater than 0");
        require(token.balanceOf(msg.sender) >= amountTokens, "Insufficient token balance");
        // Transfer tokens from user to contract
        token.transferFrom(msg.sender, address(this), amountTokens);

        // Apply swap fee
        uint fee = (amountTokens * swap_fee_numerator) / swap_fee_denominator ;
        uint amountTokensAfterFee = amountTokens - fee;
        token_fee_reserves += fee;

        // Calculate ETH to send out using the constant product formula
        uint amountETH = (eth_reserves * amountTokensAfterFee) / (token_reserves + amountTokensAfterFee);

        // Calculate the current exchange rate
    
        uint current_exchange_rate = (token_reserves  * multiplier / 10 ** 18) / eth_reserves;
        console.log("Max Exchange Rate:", max_exchange_rate);
        require(current_exchange_rate <= max_exchange_rate, "Slippage: Exchange rate too high");


        eth_reserves -= amountETH;
        // token_reserves += amountTokensAfterFee;
        token_reserves += amountTokens;
        console.log("eth_reserves:", eth_reserves);
        console.log("amountETH:", amountETH);
        console.log("fee_reserves:", amountTokensAfterFee);
        console.log("token_reserves:", token_reserves);
    
        // Transfer ETH to the user
        payable(msg.sender).transfer(amountETH);
    }


    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint max_exchange_rate)
    external
    payable 
    {
        require(msg.value > 0, "ETH amount must be greater than 0");

        uint amountETH = msg.value;
        uint fee = (amountETH * swap_fee_numerator) / swap_fee_denominator;
        uint amountETHWithFee = amountETH - fee;
        eth_fee_reserves += fee;

        require(eth_reserves > 0 && token_reserves > 0, "Insufficient liquidity in the pool");

        uint amountTokens = (amountETHWithFee * token_reserves) / (amountETHWithFee + eth_reserves);
        uint current_exchange_rate = (eth_reserves  * multiplier / 10 ** 18) / token_reserves;
        require(current_exchange_rate <= max_exchange_rate, "Slippage: Exchange rate too high");
        console.log("Current Exchange Rate:", current_exchange_rate);
        console.log("Max Exchange Rate:", max_exchange_rate);
        require(token_reserves >= amountTokens, "Insufficient token reserves");

        console.log("eth_reserves:", eth_reserves);
        console.log("token_reserves:", token_reserves);
        eth_reserves += amountETH;
        token_reserves -= amountTokens;
        console.log("eth_reserves:", eth_reserves);
        console.log("token_reserves:", token_reserves);

        token.transfer(msg.sender, amountTokens);
    }
}
/**
 * address(this): the address of this contract - exchange contract
 */