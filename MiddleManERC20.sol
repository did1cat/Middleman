// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MiddleManERC20 is Ownable, AccessControl {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant ROLE_FREE = keccak256("ROLE_FREE");
    // fee thousandths
    uint8 public feeRate = 4;
    uint256 _feeCount;
    mapping(bytes32 => bool) orderMapping;

    event CreateOrder(
        bytes32 indexed orderId,
        address indexed sender,
        address indexed recipient,
        address token,
        string tokenSymbol,
        uint256 amount,
        uint256 fee,
        string remark,
        uint256 draftAt
    );

    // executeType: 1 confirmed, 2 refunded
    event ExecuteOrder(
        bytes32 indexed orderId,
        address indexed sender,
        address indexed recipient,
        uint256 completedAt,
        uint8 executeType,
        address operator
    );

    event WithdrawFee(address indexed sender, uint256 amount);

    modifier onlyAdmin() {
        _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, owner());
    }

    function updateFeeRate(uint8 _feeRate) public onlyAdmin {
        feeRate = _feeRate;
    }

    function grantRoleBatch(bytes32 role, address[] memory toBeGrantedAddrs)
        public
        onlyAdmin
    {
        for (uint256 i = 0; i < toBeGrantedAddrs.length; i++) {
            _grantRole(role, toBeGrantedAddrs[i]);
        }
    }

    function createOrder(
        address token,
        string calldata tokenSymbol,
        address recipient,
        uint256 amount,
        uint256 fee,
        string calldata remark
    ) external {
        uint8 senderFeeRate = feeRate;
        if (hasRole(ROLE_FREE, msg.sender)) {
            senderFeeRate = 0;
        }
        require(
            amount.div(1000).mul(senderFeeRate) == fee,
            "MiddleMan: wrong service fee"
        );
        // generate id
        bytes32 id = keccak256(
            abi.encodePacked(
                token,
                tokenSymbol,
                msg.sender,
                recipient,
                amount,
                fee,
                uint256(block.timestamp)
            )
        );
        require(orderMapping[id] == false, "MiddleMan: order exist");
        orderMapping[id] = true;
        IERC20(token).safeTransferFrom(
            msg.sender,
            address(this),
            amount.add(fee)
        );
        emit CreateOrder(
            id,
            msg.sender,
            recipient,
            token,
            tokenSymbol,
            amount,
            fee,
            remark,
            block.timestamp
        );
    }

    function confirmOrder(
        address token,
        string calldata tokenSymbol,
        address recipient,
        uint256 amount,
        uint256 fee,
        uint256 draftAt
    ) external {
        bytes32 id = keccak256(
            abi.encodePacked(
                token,
                tokenSymbol,
                msg.sender,
                recipient,
                amount,
                fee,
                draftAt
            )
        );
        require(orderMapping[id] == true, "MiddleMan: order not exist");
        delete orderMapping[id];
        _feeCount = _feeCount.add(fee);
        IERC20(token).safeTransfer(recipient, amount);
        emit ExecuteOrder(
            id,
            msg.sender,
            recipient,
            block.timestamp,
            1,
            msg.sender
        );
    }

    function confirmOrderByAdmin(
        address token,
        string calldata tokenSymbol,
        address sender,
        address recipient,
        uint256 amount,
        uint256 fee,
        uint256 draftAt
    ) external onlyAdmin {
        bytes32 id = keccak256(
            abi.encodePacked(
                token,
                tokenSymbol,
                sender,
                recipient,
                amount,
                fee,
                draftAt
            )
        );
        require(orderMapping[id] == true, "MiddleMan: order not exist");
        delete orderMapping[id];
        _feeCount = _feeCount.add(fee);
        IERC20(token).safeTransfer(recipient, amount);

        emit ExecuteOrder(
            id,
            sender,
            recipient,
            block.timestamp,
            1,
            msg.sender
        );
    }

    function refundOrderByRecipient(
        address token,
        string calldata tokenSymbol,
        address sender,
        address recipient,
        uint256 amount,
        uint256 fee,
        uint256 draftAt
    ) external {
        require(
            msg.sender == recipient,
            "MiddleMan: only recipient can refund"
        );
        bytes32 id = keccak256(
            abi.encodePacked(
                token,
                tokenSymbol,
                sender,
                recipient,
                amount,
                fee,
                draftAt
            )
        );
        require(orderMapping[id] == true, "MiddleMan: order not exist");
        delete orderMapping[id];
        _feeCount = _feeCount.add(fee);
        IERC20(token).safeTransfer(sender, amount);
        emit ExecuteOrder(
            id,
            sender,
            recipient,
            block.timestamp,
            2,
            msg.sender
        );
    }

    function refundOrderByAdmin(
        address token,
        string calldata tokenSymbol,
        address sender,
        address recipient,
        uint256 amount,
        uint256 fee,
        uint256 draftAt
    ) external onlyAdmin {
        bytes32 id = keccak256(
            abi.encodePacked(
                token,
                tokenSymbol,
                sender,
                recipient,
                amount,
                fee,
                draftAt
            )
        );
        require(orderMapping[id] == true, "MiddleMan: order not exist");
        delete orderMapping[id];
        _feeCount = _feeCount.add(fee);
        IERC20(token).safeTransfer(sender, amount);
        emit ExecuteOrder(
            id,
            sender,
            recipient,
            block.timestamp,
            2,
            msg.sender
        );
    }

    function getFeeCount() external view onlyAdmin returns (uint256) {
        return _feeCount;
    }

    function withdrawFeeCount(address token, uint256 amount)
        external
        onlyAdmin
    {
        require(_feeCount >= amount, "MiddleMan: insufficient fee count");
        _feeCount = _feeCount.sub(amount);
        IERC20(token).safeTransfer(msg.sender, amount);
        emit WithdrawFee(msg.sender, amount);
    }

    receive() external payable {
        require(false, "MiddleMan: not accepting ether directly");
    }
}
