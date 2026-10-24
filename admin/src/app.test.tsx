import { render, screen, waitFor, fireEvent, cleanup } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { App, SetupNeeded } from './App';
import { validateConfig, loadConfig } from './config';
import type { Account, AdminApi } from './api';

afterEach(cleanup);

const pending: Account = {
  uid: 'u1', businessName: 'Cafe One', ownerName: 'Ali', phone: '0300', city: 'Lahore', country: 'PK', email: 'a@x.pk', status: 'pending', plan: null, feeMinor: 0, currency: 'PKR',
  expiresAt: null, customerId: null, businessId: null, licenseId: null, approvedPhones: [], phoneRequests: ['p1'], blockedPhones: [], maxPhones: 1, disabledModules: [], adminMessage: '', createdAt: new Date('2026-10-01'), appVersion: '0.1.0', todayNetMinor: 0, todayAt: null,
};

function fake(over: Partial<AdminApi> = {}): AdminApi {
  const nope = async () => { throw new Error('unused'); };
  return {
    onAuth: cb => { cb({ uid: 'adm', email: 'a@dt.test' }); return () => {}; },
    signIn: async () => {}, signOut: async () => {}, resetPassword: async () => {}, isAdmin: async () => true, ownerClaimed: async () => true, claimSuperAdmin: vi.fn(async () => {}),
    accounts: async () => [pending], account: async () => pending, approve: vi.fn(async () => {}), patchAccount: nope, setStatus: vi.fn(async () => {}), approvePhone: nope, removePhone: nope,
    notes: async () => '', setNotes: nope, days: async () => [], devices: async () => [], setDeviceBlocked: nope, deleteDevice: nope, invoices: async () => [], invoice: async () => null,
    createInvoice: nope, recordPayment: nope, voidInvoice: nope, verifyInvoice: async () => null, threads: async () => [], messages: async () => [], sendMessage: nope, markRead: async () => {},
    clearChat: nope, deleteChat: nope,
    getBranding: async () => ({ appName: '', contact: '', whatsapp: '', email: '', supportMessage: '' }), setBranding: nope,
    getAppControl: async () => ({ offlineDays: 7, notice: '', latestVersion: '', minVersion: '', updateLink: '' }), setAppControl: nope,
    getBilling: async () => ({ company: '', address: '', bank: '', accountTitle: '', accountNo: '', terms: '', paymentQr: '', signature: '', reminderTemplate: '', planPrices: { monthly: 250000 } }), setBilling: nope,
    admins: async () => [{ uid: 'adm' }], addAdmin: nope, removeAdmin: nope, auditLog: async () => [],
    ...over,
  };
}

describe('config', () => {
  it('rejects empty and example values', () => {
    expect(validateConfig(null).problem).toBeTruthy();
    expect(validateConfig({ apiKey: 'YOUR-WEB-API-KEY', authDomain: 'a', projectId: 'p', appId: 'x' }).problem).toMatch(/apiKey/);
    expect(validateConfig({ apiKey: 'k', authDomain: 'a.firebaseapp.com', projectId: 'p', appId: 'x' }).config?.projectId).toBe('p');
  });
  it('reports missing config instead of crashing', async () => {
    const r = await loadConfig((async () => new Response('', { status: 404 })) as typeof fetch);
    expect(r.problem).toMatch(/No Firebase config/);
  });
});

describe('panel', () => {
  it('shows setup screen when unconfigured', () => { render(<SetupNeeded problem="missing" />); expect(screen.getByText('Setup needed')).toBeTruthy(); });
  it('offers "Become Super Admin" only while nobody has claimed the project', async () => {
    const api = fake({ isAdmin: async () => false, ownerClaimed: async () => false });
    render(<App api={api} />);
    fireEvent.click(await screen.findByText('Become Super Admin'));
    await waitFor(() => expect(api.claimSuperAdmin).toHaveBeenCalledWith('adm'));
  });
  it('shows the uid, not the claim button, once claimed', async () => {
    render(<App api={fake({ isAdmin: async () => false })} />);
    expect(await screen.findByText('adm')).toBeTruthy();
    expect(screen.queryByText('Become Super Admin')).toBeNull();
  });
  it('shows the sign-in form when signed out and surfaces errors', async () => {
    const api = fake({ onAuth: cb => { cb(null); return () => {}; }, signIn: async () => { throw new Error('wrong password'); } });
    render(<App api={api} />);
    fireEvent.click(await screen.findByText('Sign in'));
    expect((await screen.findByRole('alert')).textContent).toBe('wrong password');
  });
  it('switches app features off for one restaurant and saves only the switched-off ones', async () => {
    const patch = vi.fn(async () => {});
    const api = fake({ patchAccount: patch });
    render(<App api={api} />);
    fireEvent.click(await screen.findByText('Restaurants'));
    fireEvent.click(await screen.findByText('Cafe One'));
    await screen.findByText('App features');
    expect((screen.getByLabelText('Food tokens & coupons') as HTMLInputElement).checked).toBe(true);
    fireEvent.click(screen.getByLabelText('Food tokens & coupons'));
    fireEvent.click(screen.getByLabelText('Tables (dine-in)'));
    fireEvent.click(screen.getByText('Save features'));
    await waitFor(() => expect(patch).toHaveBeenCalledWith('u1', { disabledModules: ['tables', 'tokens'] }));
  });

  it('approves a pending restaurant with the chosen plan and fee', async () => {
    const api = fake();
    render(<App api={api} />);
    fireEvent.click(await screen.findByText('Restaurants'));
    fireEvent.click(await screen.findByText('Cafe One'));
    fireEvent.change(await screen.findByLabelText('Fee'), { target: { value: '1,500' } });
    fireEvent.click(screen.getByText('Approve'));
    await waitFor(() => expect(api.approve).toHaveBeenCalled());
    const [uid, plan, fee, exp] = (api.approve as ReturnType<typeof vi.fn>).mock.calls[0];
    expect([uid, plan, fee]).toEqual(['u1', 'monthly', 150000]);
    expect(exp).toBeInstanceOf(Date);
  });
  it('requires a message to suspend', async () => {
    const api = fake({ account: async () => ({ ...pending, status: 'active', phoneRequests: [] }) });
    render(<App api={api} />);
    fireEvent.click(await screen.findByText('Restaurants'));
    fireEvent.click(await screen.findByText('Cafe One'));
    fireEvent.click(await screen.findByText('Suspend'));
    expect((await screen.findByRole('alert')).textContent).toMatch(/message/);
    expect(api.setStatus).not.toHaveBeenCalled();
  });
});
