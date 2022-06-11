// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

//this is for "IERC20.sol";
interface IERC20 {
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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

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
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract CentralContract {
    mapping(address => uint256) private _balances;

    mapping(address => uint256) private _totAllST;
    mapping(address => uint256) private _totAllBT;
    mapping(address => uint256) private _claimST;
    mapping(address => uint256) private _claimBT;

    mapping(address => bool) private _wlMember;

    mapping(address => mapping(address => uint256)) private _allowances;

    IERC20 public _bt;
    IERC20 public _st;
    uint256 private _totalSupply;
    address private _manager;
    address private _centralContract;
    address[] private _whiteList;
    string private _name;
    string private _symbol;
    address private _creator;
    uint256 public _totST;
    uint256 public _totBT;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        IERC20 bt_,
        IERC20 st_
    ) {
        _name = name_;
        _symbol = symbol_;
        _creator = msg.sender;
        _bt = bt_;
        _st = st_;
    }

    //VIEWS VIEWS VIEWS VIEWS
    //VIEWS VIEWS VIEWS VIEWS
    //VIEWS VIEWS VIEWS VIEWS
    /**
    /**
     * @dev this is just getting who is "manager" view for central contract
     */
    function getCM() public view virtual returns (address) {
        return _manager;
    }

    /**
     * @dev this is just getting "whiteList" view for public
     */
    function WlMember(address acc) public view virtual returns (bool) {
        return _wlMember[acc];
    }

    /**
     * @dev this is just getting "totALlocatedBT[investor]" view for public
     */
    function totAllBT(address acc) public view virtual returns (uint256) {
        return _totAllBT[acc];
    }

    /**
     * @dev this is just getting "totALlocatedST[investor]" view for public
     */
    function totAllST(address acc) public view virtual returns (uint256) {
        return _totAllST[acc];
    }

    /**
     * @dev this is just getting "claimBT[investor]" view for public
     */
    function claimBT(address acc) public view virtual returns (uint256) {
        return _claimBT[acc];
    }

    /**
     * @dev this is just getting "claimST[investor]" view for public
     */
    function claimST(address acc) public view virtual returns (uint256) {
        return _claimST[acc];
    }

    //FUNCTIONS FUNCTIONS FUNCTIONS
    //FUNCTIONS FUNCTIONS FUNCTIONS
    //FUNCTIONS FUNCTIONS FUNCTIONS

    receive() external payable {}

    //syndicator uses this function to allocate share token
    function aST(
        address investor,
        IERC20 token,
        uint256 amount
    ) public payable returns (bool) {
        require(msg.sender == _creator || msg.sender == _manager);
        require(
            token == _st,
            "aST: make sure the token is the right share token"
        );
        require(amount > 0, "aST: you must pay share tokens greater than zero");
        require(
            token.balanceOf(address(msg.sender)) >= amount,
            "aST: insufficient balance to allocate share tokens"
        );
        //token.increaseAllowance(msg.sender, address(this));
        token.transferFrom(msg.sender, address(this), amount);
        _totAllST[investor] += amount;
        _claimST[investor] += amount;
        _totST += amount;
        if (_wlMember[investor] != true) {
            _whiteList.push(investor);
            _wlMember[investor] = true;
        }
        return true;
    }

    //investor uses this function to claim share token
    function cST() public virtual returns (bool) {
        address caller = msg.sender;
        require(
            _wlMember[caller] == true,
            "only white-listed members can claim share tokens"
        );
        require(_claimST[caller] > 0, "you have 0 share token to claim");
        require(
            _st.balanceOf(address(this)) >= _claimST[caller],
            "cST: this should never happen => insufficient balance of share tokens in contract"
        );
        _st.transfer(caller, _claimST[caller]);
        _claimST[caller] = 0;
        return true;
    }

    // this function is for the syndicator to distribute backing token
    function dBT(IERC20 token, uint256 amount) public payable returns (bool) {
        require(msg.sender == _creator || msg.sender == _manager);
        require(
            token == _bt,
            "dBT: make sure you are distributing backing token"
        );
        require(
            amount > 0,
            "dBT: you must pay backing tokens greater than zero"
        );
        require(
            token.balanceOf(address(msg.sender)) >= amount,
            "dBT: you do not have sufficient balance to distribute backing tokens"
        );
        token.transferFrom(msg.sender, address(this), amount);

        for (uint256 i = 0; i < _whiteList.length; i++) {
            address a = _whiteList[i];
            uint256 currentAllocation = (_totAllST[a] * amount) / _totST;
            _totAllBT[a] += currentAllocation;
            _claimBT[a] += currentAllocation;
        }

        _totBT += amount;

        return true;
    }

    //investor uses this function to claim backing token
    function cBT() public virtual returns (bool) {
        address caller = msg.sender;
        require(
            _wlMember[caller] == true,
            "cBT: only white-listed members can claim  backing tokens"
        );
        require(_claimBT[caller] > 0, "cBT: you have 0 backing token to claim");
        require(
            _bt.balanceOf(address(this)) >= _claimBT[caller],
            "cBT: this should never happen (weird) => insufficient balance of backing tokens in contract"
        );
        _bt.transfer(caller, _claimBT[caller]);
        _claimBT[caller] = 0;
        return true;
    }

    //add a new member to whitelist
    function addWL(address newMember) public virtual returns (bool) {
        require(
            newMember != address(0),
            "addWL: you cannot add a zero address to whiteList"
        );
        _whiteList.push(newMember);
        _wlMember[newMember] = true;
        return true;
    }

    //remove a  member from whitelist
    function remWL(address member) public virtual returns (bool) {
        require(
            member != address(0),
            "remWL: you cannot remove a zero address to whiteList"
        );
        require(
            _wlMember[member] == true,
            "remWL: cannot remove member that does not exist in whitelist"
        );
        _whiteList.push(member);
        _wlMember[member] = false;
        return true;
    }

    //change contract manager
    function cCM(address manager) public virtual returns (bool) {
        _manager = manager;
        return true;
    }
}
