# Oracle Integration

This document describes the Oracle integration in the Native Staking system, which is responsible for price feed data and token conversion between XFI and MPX.

## Oracle Architecture

The Native Staking system uses a multi-layer Oracle architecture:

[![Oracle Architecture](https://mermaid.ink/img/pako:eNp9kstOwzAQRX9l5FWQmjZNFtCklDd0hViwMMaJo9TKi-LH0FTNv-PEfQi1s7Dkc-_MnbGnCEXJARFC8vzKj0Vjhcw1BJ-ecff17e2Ru68eCjJ_gPE4uXNdwghU1QCyAcR_G9bVOHkC6z8pAZUYSipF_XrpXbpwM4xLADHfExXPrRtRe5c2HqBFzXONB8k5uNzxcbXeHlbrfbOGGu72Udp4vzEcZmEW9EcWXzxr9Qms7Z-uv--OzVVDy2-p_aQtKWdBzK5N9vNfFkHMCyGdZW7tQC-7wYTW2Xba9jf5N-XlJsI-Sg-RO3a-FS1RQkYuGIwfH3F30P4XlSRlJvkZoSRFXD4NTGjKpkyOMBPE1AyTdg_-gNHMDBnjk37ksswsn5o4xgwYZaxMXzQo9E-oTTzwyOc5Ym3HJnYjOHVXPjUdRUNEA0FjoLJ_5mNhP3SJdZftZpOgLrX0GLnfZkNsRQ?type=png)](https://mermaid.live/edit#pako:eNp9kstOwzAQRX9l5FWQmjZNFtCklDd0hViwMMaJo9TKi-LH0FTNv-PEfQi1s7Dkc-_MnbGnCEXJARFC8vzKj0Vjhcw1BJ-ecff17e2Ru68eCjJ_gPE4uXNdwghU1QCyAcR_G9bVOHkC6z8pAZUYSipF_XrpXbpwM4xLADHfExXPrRtRe5c2HqBFzXONB8k5uNzxcbXeHlbrfbOGGu72Udp4vzEcZmEW9EcWXzxr9Qms7Z-uv--OzVVDy2-p_aQtKWdBzK5N9vNfFkHMCyGdZW7tQC-7wYTW2Xba9jf5N-XlJsI-Sg-RO3a-FS1RQkYuGIwfH3F30P4XlSRlJvkZoSRFXD4NTGjKpkyOMBPE1AyTdg_-gNHMDBnjk37ksswsn5o4xgwYZaxMXzQo9E-oTTzwyOc5Ym3HJnYjOHVXPjUdRUNEA0FjoLJ_5mNhP3SJdZftZpOgLrX0GLnfZkNsRQ)

1. **UnifiedOracle**
   - Central Oracle component in the system
   - Aggregates price data from external sources
   - Handles token conversion calculations
   - Provides fallback mechanisms for price data

2. **DIA Oracle**
   - External Oracle providing XFI/USD price data
   - Implements standardized Oracle interface
   - Provides data with timestamp for freshness checks

3. **PriceConverter Library**
   - Utility functions for token conversions
   - Handles calculation logic between different tokens
   - Abstracts conversion complexity from core contracts

## Price Data Flow

The process for retrieving and using price data follows this flow:

[![Price Data Flow](https://mermaid.ink/img/pako:eNp9U11v2jAU_StWnlqJEhIKD4QQSoGnaXvag5AeRk2QCbeFJbGzOJRW_PddOwG2tnuyfe_5Ojf3HAdDXjKIIGrTT_qiSs0EU-Bt3maDt4-PKR2kBYw4_4Lj8ehtNmMxEFIBIwWkK6Nn1TAZfw6U9yAlqNKykjnT7-f-2ZV_NE5yAJi29_u9KDvUwJ2TN38BVlMMYujqYSmNZVs7a-ywrRosSbkL9f27k1EMaRs06d3Lw5w-V4IWTFXQTbKg6CbBKuRqabiGu0XFU4hQK6xYLLdcHDIKcepAZf_zXeaVUQW0lYm_s5xKvZg5TplLlIq1mEYdqW3E5gPZdkJJ_kNtUDnLpYP8TvnXEUyT09G8C3qEg93mP4DfdJl9_Y2NHUJFTOqCToOV6SLDwVQKGmxaIHq0ysZn4o4Cbo7CnVpEXb28-kbCcVZMDPPtPCTJXVRgK0l2FI3DnXPdOy_LRbvWM4EbAIXRyVf2ow8tYiS6D8O4V3TNRcXdbLRZQ7D1wG7BWgx3fU8Q1r16NWNjzX4_h_qKoEZZtk5Z1_LoX9BQkFsvblFGbWzf_pO6XYRwK_iULJgM_E8ZgN-NZvlchxF3zN2I1fD-FUatdVg9Zct7YWsrbCIa9uJlVZBIKMTuXBiJUh2DTbmmX4XOHaWCf-NR3Uh_o6JVPFZlCcS0h2fwAaKQvBWqpAaaWK9JqZ_QJp40bJxv_AbcnGzf?type=png)](https://mermaid.live/edit#pako:eNp9U11v2jAU_StWnlqJEhIKD4QQSoGnaXvag5AeRk2QCbeFJbGzOJRW_PddOwG2tnuyfe_5Ojf3HAdDXjKIIGrTT_qiSs0EU-Bt3maDt4-PKR2kBYw4_4Lj8ehtNmMxEFIBIwWkK6Nn1TAZfw6U9yAlqNKykjnT7-f-2ZV_NE5yAJi29_u9KDvUwJ2TN38BVlMMYujqYSmNZVs7a-ywrRosSbkL9f27k1EMaRs06d3Lw5w-V4IWTFXQTbKg6CbBKuRqabiGu0XFU4hQK6xYLLdcHDIKcepAZf_zXeaVUQW0lYm_s5xKvZg5TplLlIq1mEYdqW3E5gPZdkJJ_kNtUDnLpYP8TvnXEUyT09G8C3qEg93mP4DfdJl9_Y2NHUJFTOqCToOV6SLDwVQKGmxaIHq0ysZn4o4Cbo7CnVpEXb28-kbCcVZMDPPtPCTJXVRgK0l2FI3DnXPdOy_LRbvWM4EbAIXRyVf2ow8tYiS6D8O4V3TNRcXdbLRZQ7D1wG7BWgx3fU8Q1r16NWNjzX4_h_qKoEZZtk5Z1_LoX9BQkFsvblFGbWzf_pO6XYRwK_iULJgM_E8ZgN-NZvlchxF3zN2I1fD-FUatdVg9Zct7YWsrbCIa9uJlVZBIKMTuXBiJUh2DTbmmX4XOHaWCf-NR3Uh_o6JVPFZlCcS0h2fwAaKQvBWqpAaaWK9JqZ_QJp40bJxv_AbcnGzf)

1. **NativeStaking** contract requires XFI to MPX conversion
2. It calls the **PriceConverter** library's `toMPX()` function
3. The library requests prices from the **UnifiedOracle**
4. **UnifiedOracle** attempts to get XFI/USD price from **DIA Oracle**
5. If DIA Oracle price is fresh (within threshold), it's used for calculation
6. If DIA Oracle price is stale or unavailable, fallback price is used
7. **UnifiedOracle** provides both XFI and MPX prices
8. **PriceConverter** calculates MPX equivalent using the formula: `mpxAmount = (xfiAmount * xfiPrice) / mpxPrice`
9. The result is returned to the **NativeStaking** contract for use in operations

## UnifiedOracle Implementation

The UnifiedOracle contract serves as a bridge between external oracles and the Native Staking system:

```solidity
contract UnifiedOracle is IOracle, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    // Roles
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    
    // Constants
    uint256 private constant PRICE_FRESHNESS_THRESHOLD = 1 hours;
    uint256 private constant DIA_PRECISION = 1e8;  // DIA uses 8 decimals
    uint256 private constant PRICE_PRECISION = 1e18; // We use 18 decimals
    
    // Oracle connections
    IDIAOracle private _diaOracle;
    
    // Price data
    uint256 private _mpxPrice;
    mapping(string => uint256) private _fallbackPrices;
    
    // Events
    event PriceUpdated(string indexed symbol, uint256 price);
}
```

### Key Functions

1. **Price Retrieval**

```solidity
function getXFIPrice() public view override returns (uint256 price, uint256 timestamp) {
    // Try to get price from DIA oracle
    (uint128 diaPrice, uint128 diaTimestamp) = _diaOracle.getValue("XFI/USD");
    
    // Check if price is fresh (within threshold)
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
```

2. **Token Conversion**

```solidity
function convertXFItoMPX(uint256 xfiAmount) external view override returns (uint256) {
    if (xfiAmount == 0 || _mpxPrice == 0) return 0;
    
    (uint256 xfiPrice, ) = getXFIPrice();
    if (xfiPrice == 0) return 0;
    
    // Convert XFI to MPX using the formula:
    // mpxAmount = xfiAmount * xfiPrice / mpxPrice
    return (xfiAmount * xfiPrice) / _mpxPrice;
}
```

3. **Price Setting**

```solidity
function setMPXPrice(uint256 price) external override onlyRole(ORACLE_UPDATER_ROLE) {
    require(price > 0, "Invalid price");
    _mpxPrice = price;
    
    emit PriceUpdated("MPX", price);
}

function setPrice(string calldata symbol, uint256 price) external onlyRole(ORACLE_UPDATER_ROLE) {
    require(price > 0, "Invalid price");
    _fallbackPrices[symbol] = price;
    
    emit PriceUpdated(symbol, price);
}
```

## PriceConverter Library

The PriceConverter library handles all token conversion calculations:

```solidity
library PriceConverter {
    /**
     * @dev Converts XFI amount to MPX amount using the oracle
     * @param oracle The oracle contract with price data
     * @param xfiAmount The amount of XFI to convert
     * @return The equivalent amount of MPX tokens
     */
    function toMPX(IOracle oracle, uint256 xfiAmount) internal view returns (uint256) {
        if (xfiAmount == 0) return 0;
        
        // Get prices from the oracle
        uint256 xfiPrice = oracle.getPrice("XFI");
        uint256 mpxPrice = oracle.getMPXPrice();
        
        // If either price is zero, we can't perform the conversion
        if (xfiPrice == 0 || mpxPrice == 0) return 0;
        
        // Convert using cross-multiplication: 
        // xfiAmount * xfiPrice / mpxPrice = mpxAmount
        return (xfiAmount * xfiPrice) / mpxPrice;
    }
    
    /**
     * @dev Converts XFI amount to USD value
     * @param oracle The oracle contract with price data
     * @param xfiAmount The amount of XFI to convert
     * @return The USD value of the XFI amount
     */
    function toUSD(IOracle oracle, uint256 xfiAmount) internal view returns (uint256) {
        if (xfiAmount == 0) return 0;
        
        // Get XFI price from the oracle
        uint256 xfiPrice = oracle.getPrice("XFI");
        
        // Convert using multiplication
        return xfiAmount * xfiPrice / 1e18;
    }
}
```

## Security Considerations

### Price Manipulation Resistance

The Oracle system incorporates several safety measures to resist price manipulation:

1. **Freshness Checks**
   - Prices older than the freshness threshold (1 hour) are considered stale
   - Stale prices trigger fallback mechanisms

2. **Fallback Prices**
   - Manual fallback prices can be set by authorized oracle updaters
   - Provides resilience against external oracle outages

3. **Role-Based Access**
   - Only addresses with the ORACLE_UPDATER_ROLE can modify prices
   - Prevents unauthorized price manipulation

4. **Precision Handling**
   - Careful handling of different decimal precisions (8 for DIA, 18 for internal)
   - Prevents mathematical errors during conversion

### Integration Best Practices

When integrating with the Oracle system:

1. **Check for Zero Values**
   - Always check for zero prices before calculations
   - Zero prices indicate oracle failure or initialization issues

2. **Handle Price Changes**
   - Applications should gracefully handle price fluctuations
   - Implement slippage protection for user operations

3. **Monitor Oracle Events**
   - Track `PriceUpdated` events for price changes
   - Implement alerts for significant price deviations

4. **Regular Updates**
   - Ensure fallback prices are regularly updated
   - Validate external oracle data quality

## Monitoring and Maintenance

For proper Oracle system operation:

1. **Regular Health Checks**
   - Verify DIA Oracle connection status
   - Check price freshness and fallback availability

2. **Price Deviation Monitoring**
   - Implement alerts for significant price deviations
   - Compare DIA Oracle prices with other market sources

3. **Fallback Price Updates**
   - Regularly update fallback prices based on market data
   - Document the fallback price update methodology

4. **Access Control Audits**
   - Regularly review addresses with ORACLE_UPDATER_ROLE
   - Rotate compromised keys immediately

For more details on Oracle interfaces and implementation, refer to the contract source code in the repository. 