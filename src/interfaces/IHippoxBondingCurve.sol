// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/// @title IHippoxBondingCurve
/// @notice Interface for the HippoxBondingCurve memecoin launchpad.
interface IHippoxBondingCurve {
    /// @notice Emitted when the launch is configured.
    event LaunchConfigured(
        uint256 virtualSolReserves,
        uint256 virtualTokenReserves,
        uint256 realTokenReserves,
        uint256 graduationSolThreshold,
        address treasury
    );
    /// @notice Emitted when a buyer purchases tokens.
    event TokensPurchased(
        address indexed buyer,
        uint256 tokenAmount,
        uint256 solCost,
        uint256 newVirtualSolReserves,
        uint256 newVirtualTokenReserves
    );
    /// @notice Emitted when a seller sells tokens back to the curve.
    event TokensSold(
        address indexed seller,
        uint256 tokenAmount,
        uint256 solReturned,
        uint256 newVirtualSolReserves,
        uint256 newVirtualTokenReserves
    );
    /// @notice Emitted when the launch graduates.
    event Graduated(
        uint256 realSolReserves,
        uint256 remainingTokens,
        address indexed treasury
    );
    /// @notice Emitted when the owner withdraws proceeds.
    event ProceedsWithdrawn(address indexed to, uint256 amount);
    /// @notice Emitted when pause state changes.
    event PausedSet(bool paused);
    /// @notice Emitted when ownership is transferred.
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    function currentPrice() external view returns (uint256);
    function quoteBuy(
        uint256 tokenAmount
    ) external view returns (uint256 solCost);
    function quoteSell(
        uint256 tokenAmount
    ) external view returns (uint256 solReturned);
    function buy(uint256 tokenAmount) external payable;
    function sell(uint256 tokenAmount) external;
    function withdrawProceeds(address to, uint256 amount) external;
    function setPaused(bool paused) external;
    function transferOwnership(address newOwner) external;
}
