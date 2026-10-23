import { describe, expect, it } from 'vitest';
import { addMonths, customerId, daysLeft, effectiveStatus, expiryFor, fillTemplate, invoiceNumber, isOnline, parseMoneyToMinor, whatsappLink } from './domain';

const d = (s: string) => new Date(s + 'T12:00:00');

describe('plans', () => {
  it('clamps month ends', () => { expect(addMonths(d('2026-01-31'), 1).getDate()).toBe(28); });
  it('trial is 14 days from now', () => { expect(expiryFor('trial', d('2026-10-01'), null)).toEqual(d('2026-10-15')); });
  it('renewal extends from a future expiry, not from today', () => {
    expect(expiryFor('monthly', d('2026-10-01'), d('2026-10-20'))).toEqual(d('2026-11-20'));
  });
  it('renewal after expiry starts today', () => {
    expect(expiryFor('monthly', d('2026-10-01'), d('2026-09-01'))).toEqual(d('2026-11-01'));
  });
  it('lifetime never expires and custom must be in the future', () => {
    expect(expiryFor('lifetime', d('2026-10-01'), null)).toBeNull();
    expect(() => expiryFor('custom', d('2026-10-01'), null, d('2026-09-01'))).toThrow();
    expect(expiryFor('custom', d('2026-10-01'), null, d('2026-12-01'))).toEqual(d('2026-12-01'));
  });
});

describe('status', () => {
  it('active past expiry is expired', () => {
    expect(effectiveStatus('active', d('2026-10-01'), d('2026-10-02'))).toBe('expired');
    expect(effectiveStatus('active', null, d('2026-10-02'))).toBe('active');
    expect(effectiveStatus('suspended', d('2026-10-01'), d('2026-10-02'))).toBe('suspended');
  });
  it('days left rounds up', () => { expect(daysLeft(d('2026-10-05'), d('2026-10-01'))).toBe(4); expect(daysLeft(null, d('2026-10-01'))).toBeNull(); });
});

describe('ids, money, messages', () => {
  it('formats ids', () => { expect(customerId(7)).toBe('DTC-0007'); expect(invoiceNumber(d('2026-10-23'), 12)).toBe('DT-2610-0012'); });
  it('parses money exactly', () => {
    expect(parseMoneyToMinor('1,500.5')).toBe(150050);
    expect(parseMoneyToMinor('10')).toBe(1000);
    expect(() => parseMoneyToMinor('1.234')).toThrow();
    expect(() => parseMoneyToMinor('abc')).toThrow();
  });
  it('fills only known placeholders', () => { expect(fillTemplate('Hi {owner}, {x}', { owner: 'Ali' })).toBe('Hi Ali, {x}'); });
  it('builds a whatsapp link with the local zero dropped', () => {
    expect(whatsappLink('0300-1234567', 'a b')).toBe('https://wa.me/3001234567?text=a%20b');
    expect(whatsappLink('+92 300 1234567', 'x')).toContain('wa.me/923001234567');
  });
  it('online = seen in last 5 minutes', () => {
    expect(isOnline(new Date(1_000_000), new Date(1_000_000 + 299_000))).toBe(true);
    expect(isOnline(new Date(1_000_000), new Date(1_000_000 + 301_000))).toBe(false);
    expect(isOnline(null, new Date())).toBe(false);
  });
});
