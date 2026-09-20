// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IHippoxBondingCurve} from "./interfaces/IHippoxBondingCurve.sol";
/// @title HippoxBondingCurve
/// @notice A pump.fun-style memecoin launchpad using a virtual-reserve
///         constant-product curve for pricing.
/// @dev Pricing model:
///        price = virtualSolReserves / virtualTokenReserves
///      Buying adds SOL to virtualSol and removes tokens from virtualToken,
///      which increases the price. Selling does the opposite.
///      When realSolReserves reaches graduationSolThreshold, the launch
///      graduates and trading stops. The owner then migrates liquidity
///      to an external DEX (handled off-chain or by a separate migrator).
contract HippoxBondingCurve is ERC20, IHippoxBondingCurve {
    // Immutable / config
    /// @notice Treasury that receives proceeds.
    address public treasury;
    /// @notice Owner of the contract.
    address public owner;
    /// @notice Whether trading is paused.
    bool public paused;
    /// @notice Whether the launch has graduated.
    bool public graduated;
    // Virtual / real reserves
    /// @notice Virtual SOL reserves used for pricing. Increases on buy,
    ///         decreases on sell.
    uint256 public virtualSolReserves;
    /// @notice Virtual token reserves used for pricing. Decreases on buy,
    ///         increases on sell.
    uint256 public virtualTokenReserves;
    /// @notice Real SOL accumulated from buys minus sells.
    uint256 public realSolReserves;
    /// @notice Real tokens still available to be sold by the curve.
    uint256 public realTokenReserves;
    /// @notice SOL threshold at which the launch graduates.
    uint256 public graduationSolThreshold;
    /// @notice Total tokens sold to buyers so far.
    uint256 public totalSold;
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "ONLY_OWNER");
        _;
    }
    modifier whenNotPaused() {
        require(!paused, "PAUSED");
        _;
    }
    modifier whenNotGraduated() {
        require(!graduated, "GRADUATED");
        _;
    }
    // Constructor
    /// @param name_ ERC20 name of the memecoin.
    /// @param symbol_ ERC20 symbol of the memecoin.
    /// @param owner_ Initial owner.
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_
    ) ERC20(name_, symbol_) {
        require(owner_ != address(0), "ZERO_OWNER");
        owner = owner_;
    }
    // Configuration
    /// @notice Configure the launch. Can only be called once, by the owner.
    /// @param _virtualSolReserves Initial virtual SOL reserves.
    /// @param _virtualTokenReserves Initial virtual token reserves.
    /// @param _realTokenReserves Tokens actually available to sell.
    /// @param _graduationSolThreshold Real SOL threshold to graduate.
    /// @param _treasury Address that receives proceeds.
    function configure(
        uint256 _virtualSolReserves,
        uint256 _virtualTokenReserves,
        uint256 _realTokenReserves,
        uint256 _graduationSolThreshold,
        address _treasury
    ) external onlyOwner {
        require(virtualSolReserves == 0, "ALREADY_CONFIGURED");
        require(_virtualSolReserves > 0, "ZERO_VIRTUAL_SOL");
        require(_virtualTokenReserves > 0, "ZERO_VIRTUAL_TOKEN");
        require(_realTokenReserves > 0, "ZERO_REAL_TOKEN");
        require(_realTokenReserves <= _virtualTokenReserves, "REAL_GT_VIRTUAL");
        require(_graduationSolThreshold > 0, "ZERO_GRAD_THRESHOLD");
        require(_treasury != address(0), "ZERO_TREASURY");
        virtualSolReserves = _virtualSolReserves;
        virtualTokenReserves = _virtualTokenReserves;
        realTokenReserves = _realTokenReserves;
        graduationSolThreshold = _graduationSolThreshold;
        treasury = _treasury;
        emit LaunchConfigured(
            _virtualSolReserves,
            _virtualTokenReserves,
            _realTokenReserves,
            _graduationSolThreshold,
            _treasury
        );
    }
    // Pricing
    /// @notice Returns the current spot price.
    function currentPrice() public view override returns (uint256) {
        if (virtualTokenReserves == 0) return 0;
        return virtualSolReserves / virtualTokenReserves;
    }
    /// @notice Quotes the SOL cost to buy `tokenAmount` tokens.
    /// @dev Constant product: (vSol + cost) * (vToken - tokenAmount) = k.
    ///      Solving for cost: cost = k / (vToken - tokenAmount) - vSol.
    function quoteBuy(
        uint256 tokenAmount
    ) public view override returns (uint256 solCost) {
        require(tokenAmount > 0, "ZERO_AMOUNT");
        require(tokenAmount <= realTokenReserves, "EXCEEDS_REAL_RESERVES");
        require(tokenAmount < virtualTokenReserves, "EXCEEDS_VIRTUAL_RESERVES");
        uint256 k = virtualSolReserves * virtualTokenReserves;
        uint256 newVirtualToken = virtualTokenReserves - tokenAmount;
        uint256 newVirtualSol = k / newVirtualToken;
        solCost = newVirtualSol - virtualSolReserves + 1; // round up
    }
    /// @notice Quotes the SOL returned for selling `tokenAmount` tokens.
    /// @dev Constant product: (vSol - refund) * (vToken + tokenAmount) = k.
    ///      Solving for refund: refund = vSol - k / (vToken + tokenAmount).
    function quoteSell(
        uint256 tokenAmount
    ) public view override returns (uint256 solReturned) {
        require(tokenAmount > 0, "ZERO_AMOUNT");
        uint256 k = virtualSolReserves * virtualTokenReserves;
        uint256 newVirtualToken = virtualTokenReserves + tokenAmount;
        uint256 newVirtualSol = k / newVirtualToken;
        solReturned = virtualSolReserves - newVirtualSol;
    }
    // Buy
    /// @notice Buy `tokenAmount` tokens with native ETH/SOL.
    /// @dev Overpayment is refunded. Underpayment reverts.
    function buy(
        uint256 tokenAmount
    ) external payable override whenNotPaused whenNotGraduated {
        uint256 cost = quoteBuy(tokenAmount);
        require(msg.value >= cost, "INSUFFICIENT_SOL");
        // Update virtual reserves.
        virtualSolReserves += cost;
        virtualTokenReserves -= tokenAmount;
        // Update real reserves.
        realSolReserves += cost;
        realTokenReserves -= tokenAmount;
        // Mint tokens to buyer.
        _mint(msg.sender, tokenAmount);
        totalSold += tokenAmount;
        // Refund overpayment.
        if (msg.value > cost) {
            (bool ok, ) = msg.sender.call{value: msg.value - cost}("");
            require(ok, "SOL_REFUND_FAILED");
        }
        emit TokensPurchased(
            msg.sender,
            tokenAmount,
            cost,
            virtualSolReserves,
            virtualTokenReserves
        );
        // Check graduation.
        if (realSolReserves >= graduationSolThreshold) {
            _graduate();
        }
    }
    // Sell
    /// @notice Sell `tokenAmount` tokens back to the curve.
    /// @dev Tokens are burned, SOL is returned from real reserves.
    function sell(
        uint256 tokenAmount
    ) external override whenNotPaused whenNotGraduated {
        require(tokenAmount > 0, "ZERO_AMOUNT");
        require(balanceOf(msg.sender) >= tokenAmount, "INSUFFICIENT_BALANCE");
        uint256 refund = quoteSell(tokenAmount);
        require(refund <= realSolReserves, "INSUFFICIENT_REAL_SOL");
        // Update virtual reserves.
        virtualSolReserves -= refund;
        virtualTokenReserves += tokenAmount;
        // Update real reserves.
        realSolReserves -= refund;
        realTokenReserves += tokenAmount;
        // Burn tokens from seller.
        _burn(msg.sender, tokenAmount);
        totalSold -= tokenAmount;
        // Send SOL back to seller.
        (bool ok, ) = msg.sender.call{value: refund}("");
        require(ok, "SOL_TRANSFER_FAILED");
        emit TokensSold(
            msg.sender,
            tokenAmount,
            refund,
            virtualSolReserves,
            virtualTokenReserves
        );
    }
    // Graduation
    /// @dev Marks the launch as graduated and stops trading. The owner is
    ///      expected to migrate liquidity to a DEX off-chain.
    function _graduate() internal {
        graduated = true;
        emit Graduated(realSolReserves, realTokenReserves, treasury);
    }
    // Proceeds
    /// @notice Owner withdraws accumulated proceeds.
    /// @dev After graduation, the owner typically withdraws everything and
    ///      seeds a DEX pool.
    function withdrawProceeds(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "ZERO_TO");
        require(amount <= realSolReserves, "EXCEEDS_REAL_SOL");
        realSolReserves -= amount;
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "SOL_TRANSFER_FAILED");
        emit ProceedsWithdrawn(to, amount);
    }
    // Pause / ownership
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PausedSet(_paused);
    }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO_NEW_OWNER");
        address previous = owner;
        owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }
    // Receive
    /// @dev Only accept ETH when not paused and not graduated.
    receive() external payable {
        require(!paused, "PAUSED");
        require(!graduated, "GRADUATED");
    }
}
