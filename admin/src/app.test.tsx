import { render, screen, waitFor, fireEvent, cleanup } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { App, SetupNeeded } from './App';
import { validateConfig, loadConfig } from './config';
import type { AdminApi, Business } from './api';

afterEach(cleanup);

const pending: Business = { id: 'b1', name: 'Biz One', owner_name: 'O', phone: '1', email: null, country: 'PK', currency: 'PKR', status: 'pending', status_note: null, created_at: '2026-01-01' };

function fake(over: Partial<AdminApi> = {}): AdminApi {
  const nope = async () => { throw new Error('unused'); };
  return {
    signIn: async () => {}, signOut: async () => {}, myRole: async () => 'owner',
    dashboard: async () => ({ businesses: { pending: 1 }, licenses: {}, devices: 0, sales_today: 0, unpaid_invoices: 2 }),
    businesses: async () => [pending], setBusinessStatus: vi.fn(async () => {}), plans: async () => [], licenses: async () => [],
    issueLicense: nope, setLicenseStatus: nope, invoices: async () => [], createInvoice: nope, recordPayment: nope,
    threads: async () => [], messages: async () => [], sendSupport: nope, audit: async () => [], company: async () => ({}), setCompany: nope,
    ...over,
  };
}

describe('config', () => {
  it('rejects empty, example and malformed values', () => {
    expect(validateConfig(null).problem).toBeTruthy();
    expect(validateConfig({ supabaseUrl: 'https://YOUR-PROJECT.supabase.co', supabaseAnonKey: 'x'.repeat(40) }).problem).toMatch(/supabaseUrl/);
    expect(validateConfig({ supabaseUrl: 'https://abc.supabase.co', supabaseAnonKey: 'short' }).problem).toMatch(/supabaseAnonKey/);
  });
  it('accepts a real-looking config and defaults the brand', () => {
    const r = validateConfig({ supabaseUrl: 'https://abc.supabase.co', supabaseAnonKey: 'k'.repeat(40) });
    expect(r.config?.brandName).toBe('Digital Target');
  });
  it('reports a missing config.json instead of crashing', async () => {
    const r = await loadConfig((async () => new Response('', { status: 404 })) as typeof fetch);
    expect(r.problem).toMatch(/config.json/);
  });
});

describe('panel', () => {
  it('shows a setup screen with no data when unconfigured', () => {
    render(<SetupNeeded problem="missing" />);
    expect(screen.getByText('Setup needed')).toBeTruthy();
  });
  it('keeps non-staff accounts on the login screen', async () => {
    render(<App api={fake({ myRole: async () => null })} brand="DT" />);
    expect(await screen.findByText(/Super Admin/)).toBeTruthy();
    expect(screen.queryByText('Businesses')).toBeNull();
  });
  it('shows an error when sign in fails', async () => {
    render(<App api={fake({ myRole: async () => null, signIn: async () => { throw new Error('bad password'); } })} brand="DT" />);
    fireEvent.click(await screen.findByText('Sign in'));
    expect((await screen.findByRole('alert')).textContent).toBe('bad password');
  });
  it('approves a pending business through the API', async () => {
    const api = fake();
    render(<App api={api} brand="DT" />);
    fireEvent.click(await screen.findByText('Businesses'));
    fireEvent.click(await screen.findByText('Approve'));
    await waitFor(() => expect(api.setBusinessStatus).toHaveBeenCalledWith('b1', 'approved', ''));
  });
  it('surfaces a backend refusal (e.g. missing note on reject)', async () => {
    const api = fake({ setBusinessStatus: async () => { throw new Error('a note is required'); } });
    render(<App api={api} brand="DT" />);
    fireEvent.click(await screen.findByText('Businesses'));
    fireEvent.click(await screen.findByText('Reject'));
    expect((await screen.findByRole('alert')).textContent).toBe('a note is required');
  });
  it('lets only the owner edit company details', async () => {
    render(<App api={fake({ myRole: async () => 'viewer' })} brand="DT" />);
    fireEvent.click(await screen.findByText('Settings'));
    expect((await screen.findByLabelText('phone') as HTMLInputElement).disabled).toBe(true);
  });
});
