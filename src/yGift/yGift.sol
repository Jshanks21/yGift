pragma solidity ^0.6.4;

import "../erc721/ERC721.sol";
import "../erc20/IERC20.sol";
import "./Controller.sol";
import "../utils/SafeMath.sol";

library SafeERC20 {
	using SafeMath for uint256;
	using Address for address;

	function safeTransfer(IERC20 token, address to, uint256 value) internal {
		callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
	}

	function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
		callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
	}

	function safeApprove(IERC20 token, address spender, uint256 value) internal {
		require((value == 0) || (token.allowance(address(this), spender) == 0),
			"SafeERC20: approve from non-zero to non-zero allowance"
		);
		callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
	}
	function callOptionalReturn(IERC20 token, bytes memory data) private {
		require(address(token).isContract(), "SafeERC20: call to non-contract");

		// solhint-disable-next-line avoid-low-level-calls
		(bool success, bytes memory returndata) = address(token).call(data);
		require(success, "SafeERC20: low-level call failed");

		if (returndata.length > 0) { // Return data is optional
			// solhint-disable-next-line max-line-length
			require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
		}
	}
}

contract yGift is ERC721("yearn Gift NFT", "yGIFT"), Controller {
	using SafeERC20 for IERC20;
	using SafeMath for uint256;

	uint256 constant MAX_LOCK_PERIOD = 30 days;

	struct Gift {
		string	name;
		address	minter;
		address	recipient;
		address	token;
		uint256	amount;
		string	imageURL;
		bool	redeemed;
		uint256	createdAt;
		uint256	lockedDuration;
	}

	Gift[] gifts;

	mapping(address => bool) supportedTokens;
	mapping(address => uint256) tokensHeld;

	event Tip(address indexed tipper, uint256 indexed tokenId, address token, uint256 amount, string message);
	event Collected(address indexed redeemer, uint256 indexed tokenId, address token, uint256 amount);

	function addTokens(address[] calldata _tokens) external onlyController {
		for (uint256 i = 0; i < _tokens.length; i++)
			supportedTokens[_tokens[i]] = true;
	}

	function removeTokens(address[] calldata _tokens) external onlyController {
		for (uint256 i = 0; i < _tokens.length; i++)
			supportedTokens[_tokens[i]] = false;
	}

	function getGift(uint256 _tokenId) public view
	returns (
		string memory,
		address,
		address,
		address,
		uint256,
		string memory,
		bool,
		uint256,
		uint256
	) {
		require(_tokenId < gifts.length, "yGift: Token ID does not exist.");
		Gift memory gift = gifts[_tokenId];
		return (
		gift.name,
		gift.minter,
		gift.recipient,
		gift.token,
		gift.amount,
		gift.imageURL,
		gift.redeemed,
		gift.createdAt,
		gift.lockedDuration
		);
	}

	function mint(
		address _to,
		address _token,
		uint256 _amount,
		string calldata _url,
		string calldata _name,
		string calldata _msg,
		uint256 _lockedDuration)
		external onlyWhitelisted {
		require(supportedTokens[_token], "yGift: ERC20 token is not supported.");
		require(IERC20(_token).balanceOf(msg.sender) >= _amount, "yGift: Not enough token balance to mint."); 
		require(_lockedDuration <= MAX_LOCK_PERIOD, "yGift: Locked period is too large");

		uint256 _id = gifts.length;
		Gift memory gift = Gift(_name, msg.sender, _to, _token, _amount, _url, false, block.timestamp, _lockedDuration);
		gifts.push(gift);
		tokensHeld[_token] = tokensHeld[_token].add(_amount);
		_safeMint(address(this), _id);
		IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
		emit Tip(msg.sender, _id, _token, _amount, _msg);
	}

	function tip(uint256 _tokenId, uint256 _amount, string memory _msg) public {
		require(_tokenId < gifts.length, "yGift: Token ID does not exist.");
		Gift storage gift = gifts[_tokenId];
		gift.amount = gift.amount.add(_amount);
		tokensHeld[gift.token] = tokensHeld[gift.token].add(_amount);
		IERC20(gift.token).safeTransferFrom(msg.sender, address(this), _amount);
		emit Tip(msg.sender, _tokenId, gift.token, _amount, _msg);
	}

	function redeem(uint256 _tokenId) public {
		require(_tokenId < gifts.length, "yGift: Token ID does not exist.");
		Gift storage gift = gifts[_tokenId];
		require(msg.sender == gift.recipient, "yGift: You are not the recipient.");
		require(gift.createdAt.add(gift.lockedDuration) >= block.timestamp, "yGift: Gift is still locked.");
		gift.redeemed = true;
		_safeTransfer(address(this), msg.sender, _tokenId, "");
	}

	function collect(uint256 _amount, uint256 _tokenId) public {
		require(_tokenId < gifts.length, "yGift: Token ID does not exist.");
		require(ownerOf(_tokenId) == msg.sender, "yGift: You are not the NFT owner.");
		Gift storage gift = gifts[_tokenId];
		require(gift.redeemed, "yGift: NFT tokens cannot be collected.");
		gift.amount = gift.amount.sub(_amount);
		tokensHeld[gift.token] = tokensHeld[gift.token].sub(_amount);
		IERC20(gift.token).safeTransferFrom(address(this), msg.sender, _amount);
		emit Collected(msg.sender, _tokenId, gift.token, _amount);
	}

	function removeDust(address _token, uint256 _amount) external onlyController {
		require (IERC20(_token).balanceOf(address(this)).sub(_amount) >= tokensHeld[_token],
			"yGift: Cannot withdraw tokens.");
		IERC20(_token).safeTransferFrom(address(this), msg.sender, _amount);
	}

	function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes calldata _data) external view returns (bytes4) {
		require(msg.sender == address(this), "yGift: Cannot receive other NFTs");
		return yGift.onERC721Received.selector;
	}
}