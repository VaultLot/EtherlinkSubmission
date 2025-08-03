#!/usr/bin/env python3
"""
Price Feed Manager - Multi-source cryptocurrency price aggregation
Fetches real-time cryptocurrency prices from multiple reliable APIs
"""

import requests
import time
from typing import Dict, List, Optional, Union
from decimal import Decimal
from datetime import datetime, timedelta
import asyncio
import aiohttp
import json
import os
from dataclasses import dataclass


@dataclass
class PriceData:
    """Price data structure with metadata"""
    symbol: str
    price: float
    source: str
    timestamp: datetime
    volume_24h: Optional[float] = None
    change_24h: Optional[float] = None
    market_cap: Optional[float] = None


class PriceFeedManager:
    """
    Advanced price feed manager with multiple data sources and fallback mechanisms
    """
    
    def __init__(self, coinmarketcap_api_key: Optional[str] = None):
        self.coinmarketcap_api_key = coinmarketcap_api_key
        self.cache = {}
        self.cache_ttl = 60  # 1 minute cache
        self.session = requests.Session()
        
        # API endpoints and configurations
        self.apis = {
            "coingecko": {
                "base_url": "https://api.coingecko.com/api/v3",
                "rate_limit": 10,  # requests per minute for free tier
                "requires_key": False
            },
            "coinpaprika": {
                "base_url": "https://api.coinpaprika.com/v1",
                "rate_limit": 20,
                "requires_key": False
            },
            "binance": {
                "base_url": "https://api.binance.com/api/v3",
                "rate_limit": 1200,  # requests per minute
                "requires_key": False
            },
            "okx": {
                "base_url": "https://www.okx.com/api/v5",
                "rate_limit": 20,
                "requires_key": False
            },
            "coinmarketcap": {
                "base_url": "https://pro-api.coinmarketcap.com/v1",
                "rate_limit": 333,  # for basic plan
                "requires_key": True
            }
        }
        
        # Symbol mappings for different APIs
        self.symbol_mappings = {
            "coingecko": {
                "BTC": "bitcoin",
                "ETH": "ethereum", 
                "USDC": "usd-coin",
                "USDT": "tether",
                "ARB": "arbitrum"
            },
            "coinpaprika": {
                "BTC": "btc-bitcoin",
                "ETH": "eth-ethereum",
                "USDC": "usdc-usd-coin",
                "USDT": "usdt-tether",
                "ARB": "arb-arbitrum"
            },
            "binance": {
                "BTC": "BTCUSDT",
                "ETH": "ETHUSDT",
                "USDC": "USDCUSDT",
                "USDT": "USDTUSDT",
                "ARB": "ARBUSDT"
            },
            "okx": {
                "BTC": "BTC-USDT",
                "ETH": "ETH-USDT",
                "USDC": "USDC-USDT",
                "USDT": "USDT-USDT",
                "ARB": "ARB-USDT"
            },
            "coinmarketcap": {
                "BTC": "BTC",
                "ETH": "ETH",
                "USDC": "USDC",
                "USDT": "USDT",
                "ARB": "ARB"
            }
        }
        
        print("✅ Price Feed Manager initialized")
    
    def _is_cache_valid(self, symbol: str, source: str = "aggregated") -> bool:
        """Check if cached price is still valid"""
        cache_key = f"{symbol}_{source}"
        if cache_key not in self.cache:
            return False
        
        cached_time = self.cache[cache_key]["timestamp"]
        return (datetime.now() - cached_time).seconds < self.cache_ttl
    
    def _get_cached_price(self, symbol: str, source: str = "aggregated") -> Optional[float]:
        """Get cached price if valid"""
        cache_key = f"{symbol}_{source}"
        if self._is_cache_valid(symbol, source):
            return self.cache[cache_key]["price"]
        return None
    
    def _cache_price(self, symbol: str, price: float, source: str = "aggregated", **metadata):
        """Cache price with metadata"""
        cache_key = f"{symbol}_{source}"
        self.cache[cache_key] = {
            "price": price,
            "timestamp": datetime.now(),
            "source": source,
            **metadata
        }
    
    # ==============================================================================
    # INDIVIDUAL API IMPLEMENTATIONS
    # ==============================================================================
    
    def fetch_coingecko_price(self, symbol: str) -> Optional[PriceData]:
        """Fetch price from CoinGecko API"""
        try:
            if symbol not in self.symbol_mappings["coingecko"]:
                return None
            
            coin_id = self.symbol_mappings["coingecko"][symbol]
            url = f"{self.apis['coingecko']['base_url']}/simple/price"
            params = {
                "ids": coin_id,
                "vs_currencies": "usd",
                "include_24hr_vol": "true",
                "include_24hr_change": "true",
                "include_market_cap": "true"
            }
            
            response = self.session.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            if coin_id in data:
                coin_data = data[coin_id]
                return PriceData(
                    symbol=symbol,
                    price=float(coin_data["usd"]),
                    source="coingecko",
                    timestamp=datetime.now(),
                    volume_24h=coin_data.get("usd_24h_vol"),
                    change_24h=coin_data.get("usd_24h_change"),
                    market_cap=coin_data.get("usd_market_cap")
                )
            
        except Exception as e:
            print(f"❌ CoinGecko API error for {symbol}: {e}")
        
        return None
    
    def fetch_coinpaprika_price(self, symbol: str) -> Optional[PriceData]:
        """Fetch price from CoinPaprika API"""
        try:
            if symbol not in self.symbol_mappings["coinpaprika"]:
                return None
            
            coin_id = self.symbol_mappings["coinpaprika"][symbol]
            url = f"{self.apis['coinpaprika']['base_url']}/tickers/{coin_id}"
            
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            if "quotes" in data and "USD" in data["quotes"]:
                usd_data = data["quotes"]["USD"]
                return PriceData(
                    symbol=symbol,
                    price=float(usd_data["price"]),
                    source="coinpaprika",
                    timestamp=datetime.now(),
                    volume_24h=usd_data.get("volume_24h"),
                    change_24h=usd_data.get("percent_change_24h"),
                    market_cap=usd_data.get("market_cap")
                )
            
        except Exception as e:
            print(f"❌ CoinPaprika API error for {symbol}: {e}")
        
        return None
    
    def fetch_binance_price(self, symbol: str) -> Optional[PriceData]:
        """Fetch price from Binance API"""
        try:
            if symbol not in self.symbol_mappings["binance"]:
                return None
            
            trading_pair = self.symbol_mappings["binance"][symbol]
            
            # Get current price
            price_url = f"{self.apis['binance']['base_url']}/ticker/price"
            price_response = self.session.get(price_url, params={"symbol": trading_pair}, timeout=10)
            price_response.raise_for_status()
            price_data = price_response.json()
            
            # Get 24h stats
            stats_url = f"{self.apis['binance']['base_url']}/ticker/24hr"
            stats_response = self.session.get(stats_url, params={"symbol": trading_pair}, timeout=10)
            stats_response.raise_for_status()
            stats_data = stats_response.json()
            
            return PriceData(
                symbol=symbol,
                price=float(price_data["price"]),
                source="binance",
                timestamp=datetime.now(),
                volume_24h=float(stats_data.get("volume", 0)),
                change_24h=float(stats_data.get("priceChangePercent", 0))
            )
            
        except Exception as e:
            print(f"❌ Binance API error for {symbol}: {e}")
        
        return None
    
    def fetch_okx_price(self, symbol: str) -> Optional[PriceData]:
        """Fetch price from OKX API"""
        try:
            if symbol not in self.symbol_mappings["okx"]:
                return None
            
            trading_pair = self.symbol_mappings["okx"][symbol]
            url = f"{self.apis['okx']['base_url']}/market/ticker"
            params = {"instId": trading_pair}
            
            response = self.session.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            if "data" in data and len(data["data"]) > 0:
                ticker_data = data["data"][0]
                return PriceData(
                    symbol=symbol,
                    price=float(ticker_data["last"]),
                    source="okx", 
                    timestamp=datetime.now(),
                    volume_24h=float(ticker_data.get("vol24h", 0)),
                    change_24h=float(ticker_data.get("chgPct", 0)) * 100  # Convert to percentage
                )
            
        except Exception as e:
            print(f"❌ OKX API error for {symbol}: {e}")
        
        return None
    
    def fetch_coinmarketcap_price(self, symbol: str) -> Optional[PriceData]:
        """Fetch price from CoinMarketCap API"""
        try:
            if not self.coinmarketcap_api_key:
                return None
            
            if symbol not in self.symbol_mappings["coinmarketcap"]:
                return None
            
            url = f"{self.apis['coinmarketcap']['base_url']}/cryptocurrency/quotes/latest"
            headers = {"X-CMC_PRO_API_KEY": self.coinmarketcap_api_key}
            params = {"symbol": symbol}
            
            response = self.session.get(url, headers=headers, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            if "data" in data and symbol in data["data"]:
                coin_data = data["data"][symbol]
                quote_data = coin_data["quote"]["USD"]
                
                return PriceData(
                    symbol=symbol,
                    price=float(quote_data["price"]),
                    source="coinmarketcap",
                    timestamp=datetime.now(),
                    volume_24h=quote_data.get("volume_24h"),
                    change_24h=quote_data.get("percent_change_24h"),
                    market_cap=quote_data.get("market_cap")
                )
            
        except Exception as e:
            print(f"❌ CoinMarketCap API error for {symbol}: {e}")
        
        return None
    
    # ==============================================================================
    # AGGREGATION AND PUBLIC METHODS
    # ==============================================================================
    
    def get_price_from_multiple_sources(self, symbol: str) -> Dict[str, Optional[PriceData]]:
        """Get price from all available sources"""
        sources = {
            "coingecko": self.fetch_coingecko_price,
            "coinpaprika": self.fetch_coinpaprika_price,
            "binance": self.fetch_binance_price,
            "okx": self.fetch_okx_price
        }
        
        # Add CoinMarketCap if API key is available
        if self.coinmarketcap_api_key:
            sources["coinmarketcap"] = self.fetch_coinmarketcap_price
        
        results = {}
        for source_name, fetch_func in sources.items():
            try:
                results[source_name] = fetch_func(symbol)
                time.sleep(0.1)  # Small delay to be respectful to APIs
            except Exception as e:
                print(f"❌ Error fetching from {source_name}: {e}")
                results[source_name] = None
        
        return results
    
    def get_price(self, symbol: str, use_cache: bool = True) -> float:
        """
        Get aggregated price for a symbol with fallback mechanisms
        """
        if use_cache:
            cached_price = self._get_cached_price(symbol)
            if cached_price is not None:
                return cached_price
        
        prices = []
        sources_data = self.get_price_from_multiple_sources(symbol)
        
        for source, price_data in sources_data.items():
            if price_data and price_data.price > 0:
                prices.append(price_data.price)
        
        if not prices:
            raise Exception(f"No valid price data found for {symbol}")
        
        # Use median price for better accuracy
        prices.sort()
        if len(prices) % 2 == 0:
            aggregated_price = (prices[len(prices)//2 - 1] + prices[len(prices)//2]) / 2
        else:
            aggregated_price = prices[len(prices)//2]
        
        # Cache the result
        if use_cache:
            self._cache_price(symbol, aggregated_price, "aggregated")
        
        return aggregated_price
    
    def get_detailed_price_data(self, symbol: str) -> Dict:
        """Get detailed price data with statistics from multiple sources"""
        sources_data = self.get_price_from_multiple_sources(symbol)
        
        valid_prices = []
        source_details = {}
        
        for source, price_data in sources_data.items():
            if price_data:
                valid_prices.append(price_data.price)
                source_details[source] = {
                    "price": price_data.price,
                    "volume_24h": price_data.volume_24h,
                    "change_24h": price_data.change_24h,
                    "market_cap": price_data.market_cap,
                    "timestamp": price_data.timestamp.isoformat()
                }
        
        if not valid_prices:
            return {"error": f"No valid price data for {symbol}"}
        
        # Calculate statistics
        valid_prices.sort()
        median_price = valid_prices[len(valid_prices)//2] if len(valid_prices) % 2 == 1 else (valid_prices[len(valid_prices)//2-1] + valid_prices[len(valid_prices)//2]) / 2
        avg_price = sum(valid_prices) / len(valid_prices)
        price_spread = (max(valid_prices) - min(valid_prices)) / avg_price * 100 if avg_price > 0 else 0
        
        return {
            "symbol": symbol,
            "aggregated_price": median_price,
            "average_price": avg_price,
            "min_price": min(valid_prices),
            "max_price": max(valid_prices),
            "price_spread_percent": price_spread,
            "sources_count": len(valid_prices),
            "sources": source_details,
            "timestamp": datetime.now().isoformat(),
            "reliability": "HIGH" if len(valid_prices) >= 3 else "MEDIUM" if len(valid_prices) >= 2 else "LOW"
        }
    
    def get_multiple_prices(self, symbols: List[str]) -> Dict[str, float]:
        """Get prices for multiple symbols efficiently"""
        results = {}
        for symbol in symbols:
            try:
                results[symbol] = self.get_price(symbol)
                time.sleep(0.2)  # Rate limiting
            except Exception as e:
                print(f"❌ Failed to get price for {symbol}: {e}")
                results[symbol] = None
        
        return results
    
    def get_market_overview(self) -> Dict:
        """Get overview of major cryptocurrency markets"""
        major_symbols = ["BTC", "ETH", "USDC", "USDT", "ARB"]
        market_data = {}
        
        for symbol in major_symbols:
            try:
                detailed_data = self.get_detailed_price_data(symbol)
                market_data[symbol] = detailed_data
                time.sleep(0.3)  # Rate limiting
            except Exception as e:
                print(f"❌ Failed to get market data for {symbol}: {e}")
                market_data[symbol] = {"error": str(e)}
        
        return {
            "timestamp": datetime.now().isoformat(),
            "market_data": market_data,
            "summary": {
                "total_symbols": len([s for s in market_data.values() if "error" not in s]),
                "failed_symbols": len([s for s in market_data.values() if "error" in s]),
                "data_quality": "HIGH" if len([s for s in market_data.values() if "error" not in s]) >= 4 else "MEDIUM"
            }
        }
    
    # ==============================================================================
    # UTILITY METHODS
    # ==============================================================================
    
    def test_api_connectivity(self) -> Dict[str, bool]:
        """Test connectivity to all APIs"""
        results = {}
        
        test_functions = {
            "coingecko": lambda: self.fetch_coingecko_price("BTC"),
            "coinpaprika": lambda: self.fetch_coinpaprika_price("BTC"),
            "binance": lambda: self.fetch_binance_price("BTC"),
            "okx": lambda: self.fetch_okx_price("BTC")
        }
        
        if self.coinmarketcap_api_key:
            test_functions["coinmarketcap"] = lambda: self.fetch_coinmarketcap_price("BTC")
        
        for api_name, test_func in test_functions.items():
            try:
                result = test_func()
                results[api_name] = result is not None and result.price > 0
            except Exception as e:
                print(f"❌ {api_name} connectivity test failed: {e}")
                results[api_name] = False
        
        return results
    
    def clear_cache(self):
        """Clear price cache"""
        self.cache.clear()
        print("✅ Price cache cleared")
    
    def get_cache_status(self) -> Dict:
        """Get cache status information"""
        now = datetime.now()
        valid_entries = 0
        
        for key, data in self.cache.items():
            if (now - data["timestamp"]).seconds < self.cache_ttl:
                valid_entries += 1
        
        return {
            "total_entries": len(self.cache),
            "valid_entries": valid_entries,
            "cache_ttl_seconds": self.cache_ttl,
            "cache_hit_ratio": valid_entries / len(self.cache) if self.cache else 0
        }


# ==============================================================================
# USAGE EXAMPLE AND TESTING
# ==============================================================================

if __name__ == "__main__":
    # Test the price feed manager
    api_key = os.getenv("COINMARKETCAP_API_KEY")
    manager = PriceFeedManager(coinmarketcap_api_key=api_key)
    
    print("🧪 Testing Price Feed Manager...")
    
    # Test API connectivity
    print("\n1. Testing API connectivity...")
    connectivity = manager.test_api_connectivity()
    for api, status in connectivity.items():
        print(f"   {api}: {'✅ Connected' if status else '❌ Failed'}")
    
    # Test individual price fetching
    print("\n2. Testing individual price fetching...")
    try:
        btc_price = manager.get_price("BTC")
        eth_price = manager.get_price("ETH")
        usdc_price = manager.get_price("USDC")
        
        print(f"   BTC: ${btc_price:.2f}")
        print(f"   ETH: ${eth_price:.2f}")
        print(f"   USDC: ${usdc_price:.4f}")
    except Exception as e:
        print(f"   ❌ Error: {e}")
    
    # Test detailed price data
    print("\n3. Testing detailed price data...")
    try:
        detailed = manager.get_detailed_price_data("ETH")
        print(f"   ETH detailed data: {json.dumps(detailed, indent=2)}")
    except Exception as e:
        print(f"   ❌ Error: {e}")
    
    # Test market overview
    print("\n4. Testing market overview...")
    try:
        overview = manager.get_market_overview()
        print(f"   Market overview generated with {overview['summary']['total_symbols']} successful symbols")
    except Exception as e:
        print(f"   ❌ Error: {e}")
    
    print("\n✅ Price Feed Manager testing complete!")