import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatAddress(address: string) {
  if (!address) return '';
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function formatTokenAmount(amount: bigint, decimals: number = 18, displayDecimals: number = 2): string {
  if (!amount) return '0.00';

  try {
    const divisor = BigInt(10 ** decimals);
    const quotient = Number(amount / divisor);
    const remainder = Number(amount % divisor);
    const decimal = remainder / Number(divisor);
    const result = quotient + decimal;

    // Handle very small numbers
    if (result < 0.01 && result > 0) {
      return result.toExponential(2);
    }

    return result.toFixed(displayDecimals);
  } catch (error) {
    console.error('Error formatting token amount:', error);
    return '0.00';
  }
}

export function parseTokenAmount(amount: string, decimals: number = 18): bigint {
  if (!amount || amount === '') return BigInt(0);

  try {
    // Remove any non-numeric characters except decimal point
    const cleanAmount = amount.replace(/[^0-9.]/g, '');

    const [whole, fraction = ''] = cleanAmount.split('.');
    const paddedFraction = fraction.padEnd(decimals, '0').slice(0, decimals);
    const result = BigInt((whole || '0') + paddedFraction);

    return result;
  } catch (error) {
    console.error('Error parsing token amount:', error);
    return BigInt(0);
  }
}

export function formatNumber(num: number, decimals: number = 2): string {
  if (num >= 1e9) {
    return (num / 1e9).toFixed(decimals) + 'B';
  }
  if (num >= 1e6) {
    return (num / 1e6).toFixed(decimals) + 'M';
  }
  if (num >= 1e3) {
    return (num / 1e3).toFixed(decimals) + 'K';
  }
  return num.toFixed(decimals);
}

export function formatPercentage(value: number, decimals: number = 2): string {
  return `${value.toFixed(decimals)}%`;
}

export function isValidAddress(address: string): boolean {
  return /^0x[a-fA-F0-9]{40}$/.test(address);
}

export function truncateText(text: string, maxLength: number): string {
  if (text.length <= maxLength) return text;
  return text.slice(0, maxLength) + '...';
}

export function formatTimeRemaining(seconds: number): string {
  const days = Math.floor(seconds / (24 * 60 * 60));
  const hours = Math.floor((seconds % (24 * 60 * 60)) / (60 * 60));
  const minutes = Math.floor((seconds % (60 * 60)) / 60);
  const secs = seconds % 60;

  if (days > 0) {
    return `${days}d ${hours}h ${minutes}m`;
  }
  if (hours > 0) {
    return `${hours}h ${minutes}m ${secs}s`;
  }
  if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  }
  return `${secs}s`;
}