// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @notice External imports
 */
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IDIAOracle.sol";

/**
 * @title UnifiedOracle
 * @dev Implementation of Oracle contract that provides price feed data
 * from DIA Oracle and handles token conversion calculations
 */
contract UnifiedOracle is 
    IOracle, 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable 
{
    /**
     * @dev Roles
     */
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    
    /**
     * @dev Constants
     */
    uint256 private constant PRICE_FRESHNESS_THRESHOLD = 1 hours;
    uint256 private constant DIA_PRECISION = 1e8;  // DIA uses 8 decimals
    uint256 private constant PRICE_PRECISION = 1e18; // We use 18 decimals
    
    /**
     * @dev Price oracle
     */
    IDIAOracle private _diaOracle;
    
    /**
     * @dev MPX price (MPX/USD with 18 decimals)
     */
    uint256 private _mpxPrice;
    
    /**
     * @dev Fallback prices (in case DIA oracle is unavailable)
     */
    mapping(string => uint256) private _fallbackPrices;
    
    /**
     * @dev Events
     */
    event PriceUpdated(string indexed symbol, uint256 price);
    
    /**
     * @dev Initializes the contract
     * @param diaOracle The address of the DIA oracle
     */
    function initialize(address diaOracle) 
        external 
        initializer 
    {
        __AccessControl_init();
        __Pausable_init();
        
        _diaOracle = IDIAOracle(diaOracle);
        
        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_UPDATER_ROLE, msg.sender);
        
        // Set default MPX price to $0.04 with 18 decimals
        _mpxPrice = 4 * 10**16;
    }
    
    /**
     * @dev Gets the current price for the given symbol
     * @param symbol The symbol to get the price for (e.g., "XFI")
     * @return The price with 18 decimals
     */
    function getPrice(string calldata symbol) 
        external 
        view 
        override 
        returns (uint256) 
    {
        if (keccak256(bytes(symbol)) == keccak256(bytes("MPX"))) {
            return _mpxPrice;
        }
        
        if (keccak256(bytes(symbol)) == keccak256(bytes("XFI"))) {
            (uint256 price, ) = getXFIPrice();
            return price;
        }
        
        // For unknown symbols, revert
        revert("Unknown symbol");
    }
    
    /**
     * @dev Gets the XFI price and timestamp
     * @return price The XFI price with 18 decimals
     * @return timestamp The timestamp of the price update
     */
    function getXFIPrice() 
        public 
        view 
        override 
        returns (uint256 price, uint256 timestamp) 
    {
        /**
         * @dev Try to get price from DIA oracle
         */
        (uint128 diaPrice, uint128 diaTimestamp) = _diaOracle.getValue("XFI/USD");
        
        /**
         * @dev Check if price is fresh (within threshold)
         */
        if (diaPrice > 0 && block.timestamp - diaTimestamp <= PRICE_FRESHNESS_THRESHOLD) {
            // Convert from DIA precision (8 decimals) to our precision (18 decimals)
            price = uint256(diaPrice) * (PRICE_PRECISION / DIA_PRECISION);
            timestamp = diaTimestamp;
        } else {
            // Use fallback price if available and DIA price is stale
            uint256 fallbackPrice = _fallbackPrices["XFI"];
            if (fallbackPrice > 0) {
                price = fallbackPrice;
                timestamp = block.timestamp; // Use current timestamp for fallback
            } else {
                // If no fallback price, return 0
                price = 0;
                timestamp = 0;
            }
        }
        
        return (price, timestamp);
    }
    
    /**
     * @dev Converts XFI amount to MPX based on current prices
     * @param xfiAmount The amount of XFI to convert
     * @return The equivalent amount of MPX
     */
    function convertXFItoMPX(uint256 xfiAmount) 
        external 
        view 
        override 
        returns (uint256) 
    {
        if (xfiAmount == 0 || _mpxPrice == 0) return 0;
        
        (uint256 xfiPrice, ) = getXFIPrice();
        if (xfiPrice == 0) return 0;
        
        return (xfiAmount * xfiPrice) / _mpxPrice;
    }
    
    /**
     * @dev Sets the MPX price
     * @param price The MPX price with 18 decimals
     */
    function setMPXPrice(uint256 price) 
        external 
        override 
        onlyRole(ORACLE_UPDATER_ROLE) 
    {
        require(price > 0, "Invalid price");
        _mpxPrice = price;
        
        emit PriceUpdated("MPX", price);
    }
    
    /**
     * @dev Gets the current MPX price
     * @return The MPX price with 18 decimals
     */
    function getMPXPrice() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _mpxPrice;
    }
    
    /**
     * @dev Sets a fallback price for a symbol
     * @param symbol The symbol to set the price for
     * @param price The price with 18 decimals
     */
    function setPrice(string calldata symbol, uint256 price) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
    {
        require(price > 0, "Invalid price");
        _fallbackPrices[symbol] = price;
        
        emit PriceUpdated(symbol, price);
    }
} 