import { render, screen, waitFor, fireEvent, cleanup } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { App, SetupNeeded } from './App';
import { validateConfig, loadConfig } from './config';
import type { Account, AdminApi } from './api';

const html2canvasMock = vi.hoisted(() => vi.fn(async () => ({ toDataURL: () => 'data:image/png;base64,AAAA' })));
vi.mock('html2canvas', () => ({ default: html2canvasMock }));

afterEach(cleanup);

const pending: Account = {
  uid: 'u1', businessName: 'Cafe One', ownerName: 'Ali', phone: '0300', city: 'Lahore', country: 'PK', email: 'a@x.pk', status: 'pending', plan: null, feeMinor: 0, currency: 'PKR',
  expiresAt: null, customerId: null, businessId: null, licenseId: null, approvedPhones: [], phoneRequests: ['p1'], blockedPhones: [], maxPhones: 1, disabledModules: [], themeId: '', themeLocked: false, adminMessage: '', createdAt: new Date('2026-10-01'), appVersion: '0.1.0', todayNetMinor: 0, todayAt: null,
};

function fake(over: Partial<AdminApi> = {}): AdminApi {
  const nope = async () => { throw new Error('unused'); };
  return {
    onAuth: cb => { cb({ uid: 'adm', email: 'a@dt.test' }); return () => {}; },
    signIn: async () => {}, signOut: async () => {}, resetPassword: async () => {}, isAdmin: async () => true, ownerClaimed: async () => true, claimSuperAdmin: vi.fn(async () => {}),
    accounts: async () => [pending], account: async () => pending, approve: vi.fn(async () => {}), patchAccount: nope, setStatus: vi.fn(async () => {}), resetOwnerPin: vi.fn(async () => {}), approvePhone: nope, removePhone: nope,
    notes: async () => '', setNotes: nope, days: async () => [], devices: async () => [], setDeviceBlocked: nope, deleteDevice: nope, invoices: async () => [], invoice: async () => null,
    createInvoice: nope, recordPayment: nope, voidInvoice: nope, verifyInvoice: async () => null, threads: async () => [], messages: async () => [], sendMessage: nope, markRead: async () => {},
    clearChat: nope, deleteChat: nope,
    getBranding: async () => ({ appName: '', contact: '', whatsapp: '', email: '', supportMessage: '' }), setBranding: nope,
    getAppControl: async () => ({ offlineDays: 7, notice: '', latestVersion: '', minVersion: '', updateLink: '' }), setAppControl: nope,
    getBilling: async () => ({ company: '', address: '', bank: '', accountTitle: '', accountNo: '', terms: '', paymentQr: '', signature: '', reminderTemplate: '', planPrices: { monthly: 250000 } }), setBilling: nope,
    admins: async () => [{ uid: 'adm', email: 'a@dt.test', name: '', perms: null, owner: true }], addAdmin: nope, setAdminPerms: nope, removeAdmin: nope, myAccess: async () => ({ owner: true, perms: null }), auditLog: async () => [],
    deleteAudit: nope, cleanAudit: nope, notices: async () => [], sendNotice: nope, deleteNotice: nope,
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
  it('resets the owner PIN from the restaurant page, digits only, 4 to 8 of them', async () => {
    const reset = vi.fn(async () => {});
    render(<App api={fake({ resetOwnerPin: reset })} />);
    fireEvent.click(await screen.findByText('Restaurants'));
    fireEvent.click(await screen.findByText('Cafe One'));
    const box = await screen.findByLabelText('New owner PIN');
    fireEvent.change(box, { target: { value: '48a21' } });
    expect((box as HTMLInputElement).value).toBe('4821');
    fireEvent.click(screen.getByText('Reset PIN'));
    await waitFor(() => expect(reset).toHaveBeenCalledWith('u1', '4821'));
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

  it('assigns and locks an app theme, or custom colours, for one restaurant', async () => {
    const patch = vi.fn(async () => {});
    render(<App api={fake({ patchAccount: patch })} />);
    fireEvent.click(await screen.findByText('Restaurants'));
    fireEvent.click(await screen.findByText('Cafe One'));
    await screen.findByText('App theme');
    fireEvent.click(screen.getByLabelText('Fresh Green'));
    fireEvent.click(screen.getByLabelText('Lock theme'));
    fireEvent.click(screen.getByText('Save theme'));
    await waitFor(() => expect(patch).toHaveBeenCalledWith('u1', { themeId: 'green', themeLocked: true }));
    fireEvent.change(screen.getByLabelText('Custom main colour'), { target: { value: '#112233' } });
    fireEvent.click(screen.getByText('Save theme'));
    await waitFor(() => expect(patch).toHaveBeenLastCalledWith('u1', { themeId: 'custom:112233,F59F00,,,outline,14', themeLocked: true }));
    fireEvent.click(screen.getByLabelText('No assigned theme'));
    fireEvent.click(screen.getByText('Save theme'));
    await waitFor(() => expect(patch).toHaveBeenLastCalledWith('u1', { themeId: '', themeLocked: false }));
  });

  it('a limited admin sees only the pages they were given', async () => {
    render(<App api={fake({ myAccess: async () => ({ owner: false, perms: ['support'] }) })} />);
    await screen.findByText('Support');
    expect(screen.queryByText('Restaurants')).toBeNull();
    expect(screen.queryByText('Invoices')).toBeNull();
    expect(screen.queryByText('Settings')).toBeNull();
    expect(screen.queryByText('Admins')).toBeNull();
    expect(screen.queryByText('Audit log')).toBeNull();
    expect(screen.getAllByText('Dashboard').length).toBeGreaterThan(0);
  });

  it('adds an admin by email and password with ticked permissions, and edits another admin\'s access', async () => {
    const add = vi.fn(async () => 'new-uid');
    const setPerms = vi.fn(async () => {});
    const admins = [
      { uid: 'adm', email: 'a@dt.test', name: 'Owner', perms: null, owner: true },
      { uid: 'u9', email: 'sara@dt.test', name: 'Sara', perms: ['support'], owner: false },
    ];
    render(<App api={fake({ admins: async () => admins, addAdmin: add, setAdminPerms: setPerms })} />);
    fireEvent.click(await screen.findByText('Admins'));
    await screen.findByText('Add an admin');
    fireEvent.change(screen.getByLabelText('Admin email'), { target: { value: 'new@dt.test' } });
    fireEvent.change(screen.getByLabelText('Admin password'), { target: { value: 'secret12' } });
    fireEvent.click(screen.getByLabelText('New admin may Invoices'));
    fireEvent.click(screen.getByLabelText('New admin may Support chat'));
    fireEvent.click(screen.getByText('Add admin'));
    await waitFor(() => expect(add).toHaveBeenCalledWith({ uid: '', email: 'new@dt.test', password: 'secret12', name: '', perms: ['restaurants', 'phones', 'notifications'] }));
    // Sara may only use Support; tick Invoices and save
    fireEvent.click(screen.getByLabelText('Sara may Invoices'));
    fireEvent.click(screen.getByText('Save access'));
    await waitFor(() => expect(setPerms).toHaveBeenCalledWith('u9', ['support', 'invoices']));
    expect(screen.getByText('Full access, always')).toBeTruthy();
  });

  it('audit log: select entries and delete them, or clean everything older than some days', async () => {
    const del = vi.fn(async () => {}); const clean = vi.fn(async () => 7);
    const entry = (id: string) => ({ id, at: new Date('2026-01-02T10:00:00'), adminEmail: 'a@dt.test', action: 'account.update', accountUid: null, details: {} });
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    render(<App api={fake({ auditLog: async () => [entry('e1'), entry('e2')], deleteAudit: del, cleanAudit: clean })} />);
    fireEvent.click(await screen.findByText('Audit log'));
    await screen.findAllByText('Changed restaurant');
    fireEvent.click(screen.getByLabelText('Select account.update e1'));
    fireEvent.click(screen.getByText('Delete selected (1)'));
    await waitFor(() => expect(del).toHaveBeenCalledWith(['e1']));
    fireEvent.change(screen.getByLabelText('Days'), { target: { value: '30' } });
    fireEvent.click(screen.getByText('Clean old entries'));
    await waitFor(() => expect(clean).toHaveBeenCalledWith(30));
    await screen.findByText('7 old entries deleted.');
  });

  it('notifications: a template fills the form; it is sent to everyone or to one restaurant', async () => {
    const send = vi.fn(async () => {});
    render(<App api={fake({ sendNotice: send })} />);
    fireEvent.click(await screen.findByText('Notifications'));
    await screen.findByText('New notification');
    fireEvent.change(screen.getByLabelText('Template'), { target: { value: 'payment' } });
    expect((screen.getByLabelText('Title') as HTMLInputElement).value).toBe('Subscription payment due');
    fireEvent.click(screen.getByText('Send'));
    await waitFor(() => expect(send).toHaveBeenCalledWith(expect.objectContaining({ title: 'Subscription payment due', kind: 'payment', target: 'all' })));
    fireEvent.change(screen.getByLabelText('Title'), { target: { value: 'Hello Cafe' } });
    fireEvent.change(screen.getByLabelText('Send to'), { target: { value: 'u1' } });
    fireEvent.click(screen.getByText('Send'));
    await waitFor(() => expect(send).toHaveBeenLastCalledWith(expect.objectContaining({ title: 'Hello Cafe', target: 'u1' })));
  });

  it('invoice: a branded sheet with a verification QR that can be saved as a PNG', async () => {
    const inv = { id: 'i1', accountUid: 'u1', number: 'INV-0001', businessName: 'Cafe One', amountMinor: 250000, discountMinor: 0, currency: 'PKR', issuedAt: new Date('2026-01-02'), dueAt: new Date('2026-01-09'), status: 'unpaid' as const, plan: null, verifyToken: 'tok123', paidAt: null };
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    render(<App api={fake({ invoices: async () => [inv], invoice: async () => inv })} />);
    fireEvent.click(await screen.findByText('Invoices'));
    fireEvent.click(await screen.findByText('Open'));
    await screen.findByTestId('invoice-sheet');
    expect(screen.getByText('INVOICE')).toBeTruthy();
    expect(screen.getAllByText('INV-0001').length).toBeGreaterThan(0);
    expect(screen.getByText('Powered by Digital Target · DT Food POS')).toBeTruthy();
    await waitFor(() => expect((screen.getByAltText('Scan to verify') as HTMLImageElement).src).toMatch(/^data:image\/png/));
    fireEvent.click(screen.getByText('Download PNG'));
    await waitFor(() => expect(html2canvasMock).toHaveBeenCalled());
    await waitFor(() => expect(click).toHaveBeenCalled());
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
