//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/*
https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.0.0/contracts/token/ERC20/IERC20.sol
*/
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract PoolTokenContract {
    struct CampaignRewardPool {
        address ownerAddress;
        uint amount;
        string token;
        bool refund;
    }

    struct Ierc20Token {
        IERC20 tokenAddress;
        bool exist;
    }

    struct CampaignCheckResponse {
        string memo;
        address ownerAddress;
        uint amount;
    }

    struct UserRewardResponse {
        string memo;
        address ownerAddress;
        bool status;
    }

    struct CampaignCheckRequest {
        string memo;
        uint amount;
    }

    struct UserRewardRequest {
        string memo;
        address userAddress;
        uint amount;
    }

    mapping(string => CampaignRewardPool) private campaignPool;
    mapping(address => mapping(string => uint)) private userPool;
    mapping(string => Ierc20Token) private ierc20Tokens;
    address private immutable dataSource;

    event Canceled(address indexed adr, string memo, uint amount);
    event CheckOne(address indexed adr, string memo, uint amount, string ticker, bool flag);
    event CheckAll(CampaignCheckResponse[] response);
    event Rewarded(UserRewardResponse[] response);

    modifier onlyOwner {
        require(msg.sender == dataSource, "Only the owner can execute this function");
        _;
    }

    constructor(address _dataSource) {
        dataSource = _dataSource;
    }

    function deposit(string memory memo) external payable {
        require(msg.value > 0, "Amount must be greater than 0");
        require(bytes(memo).length != 0, "Memo is required");

        if (campaignPool[memo].amount == 0) {
            campaignPool[memo] = CampaignRewardPool(msg.sender, msg.value, "", false);
        } else {
            campaignPool[memo].amount += msg.value;
        }
    }

    function depositIERC20(string memory memo, uint amount, string memory ticker) external {
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(memo).length != 0, "Memo is required");
        require(bytes(ticker).length != 0, "Ticker is required");
        require(ierc20Tokens[ticker].exist, "Token is not supported");

        IERC20 tokenAddress = ierc20Tokens[ticker].tokenAddress;
        require(tokenAddress.balanceOf(msg.sender) >= amount, "Not Enough Tokens");
        require(tokenAddress.allowance(msg.sender, address(this)) >= amount, "Token allowance too low");

        bool sent = tokenAddress.transferFrom(msg.sender, address(this), amount);
        require(sent, "Token transfer failed");

        if (campaignPool[memo].amount == 0) {
            campaignPool[memo] = CampaignRewardPool(msg.sender, amount, ticker, false);
        } else {
            campaignPool[memo].amount += amount;
        }
    }

    function cancel(string memory memo) external {
        require(bytes(memo).length != 0, "Memo is required");

        CampaignRewardPool memory pool = campaignPool[memo];
        require(pool.refund, "Campaign is not refundable");
        require(pool.amount > 0, "Pool is empty");

        delete campaignPool[memo];

        bool success = false;
        if (bytes(pool.token).length == 0) {
            (success,) = pool.ownerAddress.call{value: pool.amount}("");
        } else {
            IERC20 tokenAddress = ierc20Tokens[pool.token].tokenAddress;
            success = tokenAddress.transfer(msg.sender, pool.amount);
        }
        require(success, "Transfer failed");
    }

    function claim(string memory memo) external {
        uint amountToClaim = userPool[msg.sender][memo];
        require(amountToClaim > 0, "Amount to claim is zero");

        CampaignRewardPool memory pool = campaignPool[memo];

        delete userPool[msg.sender][memo];

        bool success = false;
        if (bytes(pool.token).length == 0) {
            (success,) = msg.sender.call{value: amountToClaim}("");
        } else {
            IERC20 tokenAddress = ierc20Tokens[pool.token].tokenAddress;
            success = tokenAddress.transfer(msg.sender, amountToClaim);
        }
        require(success, "Transfer failed");
    }

    function check(CampaignCheckRequest[] memory request) external onlyOwner {
        CampaignCheckResponse[] memory response = new CampaignCheckResponse[](request.length);
        uint totalFee = 0;
        for (uint i = 0; i < request.length; i++) {

            string memory memo = request[i].memo;
            CampaignRewardPool memory pool = campaignPool[memo];
            response[i] = CampaignCheckResponse(memo, pool.ownerAddress, pool.amount);

            if (pool.amount >= request[i].amount) {
                uint transferFee = pool.amount - request[i].amount;
                totalFee += transferFee;
                campaignPool[memo].amount -= transferFee;
            }
        }
        if (totalFee > 0) {
            (bool success,) = dataSource.call{value: totalFee}("");
            require(success, "Transfer failed");
        }

        emit CheckAll(response);
    }

    function refund(string memory memo) external onlyOwner {
        require(bytes(memo).length != 0, "Memo is required");
        campaignPool[memo].refund = true;
    }

    function rewardAll(UserRewardRequest[] memory request) external onlyOwner {
        UserRewardResponse[] memory response = new UserRewardResponse[](request.length);
        for (uint i = 0; i < request.length; i++) {
            address user = request[i].userAddress;
            string memory memo = request[i].memo;
            uint amount = request[i].amount;
            bool flag = campaignPool[memo].amount >= amount;

            if (flag) {
                campaignPool[memo].amount -= amount;
                userPool[user][memo] += amount;
            }

            response[i] = UserRewardResponse(memo, user, flag);
        }

        emit Rewarded(response);
    }

    function addIerc20Token(string memory ticker, address tokenAddress) external onlyOwner {
        ierc20Tokens[ticker] = Ierc20Token(IERC20(tokenAddress), true);
    }

    function getCPool(string memory memo) external onlyOwner {
        CampaignRewardPool memory pool = campaignPool[memo];
        emit CheckOne(pool.ownerAddress, memo, pool.amount, pool.token, pool.refund);
    }

    function setCPool(string memory memo, uint amount) external onlyOwner {
        require(bytes(memo).length != 0, "Memo is required");

        campaignPool[memo].amount = amount;

        CampaignRewardPool memory pool = campaignPool[memo];
        emit CheckOne(pool.ownerAddress, memo, pool.amount, pool.token, pool.refund);
    }

    function getUPool(address user, string memory memo) external onlyOwner {
        emit CheckOne(user, memo, userPool[user][memo], "", false);
    }

    function setUPool(address user, string memory memo, uint amount) external onlyOwner {
        require(bytes(memo).length != 0, "Memo is required");
        require(user != address(0), "Address is required");

        userPool[user][memo] = amount;
        emit CheckOne(user, memo, amount, "", false);
    }

    function withdraw(uint amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");

        (bool success,) = dataSource.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function withdrawIERC20(string memory ticker, uint amount) external onlyOwner {
        require(bytes(ticker).length != 0, "Ticker is required");
        require(amount > 0, "Amount must be greater than 0");

        IERC20 tokenAddress = ierc20Tokens[ticker].tokenAddress;
        bool success = tokenAddress.transfer(dataSource, amount);
        require(success, "Transfer failed");
    }
}
