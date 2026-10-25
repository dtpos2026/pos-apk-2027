import type { PlanId, Status } from './domain';

export interface Account {
  uid: string; address?: string; businessName: string; ownerName: string; phone: string; city: string; country: string; email: string;
  status: Status; plan: PlanId | null; feeMinor: number; currency: string; expiresAt: Date | null;
  customerId: string | null; businessId: string | null; licenseId: string | null;
  approvedPhones: string[]; phoneRequests: string[]; blockedPhones: string[]; maxPhones: number;
  /** Modules Digital Target switched off for this business (the app hides them and stops using them). Empty = everything on. */
  disabledModules: string[];
  /** Theme assigned to this business: a preset id ('green'...) or 'custom:MAIN,ACCENT,…'; '' = none. */
  themeId: string;
  /** True = the restaurant cannot change the theme in its app. */
  themeLocked: boolean;
  adminMessage: string; createdAt: Date | null; appVersion: string; todayNetMinor: number; todayAt: Date | null;
  /** Small picture of the restaurant's logo (a data URL) the app reports, shown on the map pin. */
  logo?: string;
  /** A PIN reset waiting for the app to pick it up (the PIN itself is never read back here). */
  pinResetPending?: boolean;
  /** When the app last applied a reset from the panel. */
  pinResetDoneAt?: Date | null;
}
export interface Device { id: string; uid: string; phoneId: string; model: string; android: string; appVersion: string; ip?: string; lastSeenAt: Date | null; locationAllowed: boolean; lat?: number; lng?: number; accuracyM?: number; locationAt?: Date | null }
export interface DayTotal { date: string; netMinor: number; bills: number; customers: number }
export interface Invoice { id: string; accountUid: string; number: string; businessName: string; amountMinor: number; discountMinor: number; currency: string; issuedAt: Date; dueAt: Date; status: 'unpaid' | 'paid' | 'void'; plan: PlanId | null; verifyToken: string; paidAt: Date | null }
export interface Thread { uid: string; businessName: string; lastMessage: string; lastAt: Date | null; unreadForAdmin: boolean }
export interface Message { id: string; sender: 'business' | 'admin'; text: string; at: Date | null }
export interface Branding { appName: string; contact: string; whatsapp: string; email: string; supportMessage: string }
export interface AppControl { offlineDays: number; notice: string; latestVersion: string; minVersion: string; updateLink: string }
export interface Billing { company: string; address: string; bank: string; accountTitle: string; accountNo: string; terms: string; paymentQr: string; signature: string; reminderTemplate: string; planPrices: Record<string, number> }
export interface AdminUser { uid: string; email: string; name: string; /** null = full access (owner, or an older admin) */ perms: string[] | null; owner: boolean }
export interface Notice { id: string; title: string; body: string; kind: string; target: string; createdAt: Date | null }
export interface NewAdmin { uid?: string; email?: string; password?: string; name?: string; perms: string[] }
export interface AuditEntry { id: string; at: Date | null; adminEmail: string; action: string; accountUid: string | null; details: Record<string, unknown> }

export type AccountPatch = Partial<Omit<Account, 'uid'>>;

/** Everything the panel does goes through this interface. FirebaseApi is the real one; tests use a fake. */
export interface AdminApi {
  onAuth(cb: (u: { uid: string; email: string } | null) => void): () => void;
  signIn(email: string, password: string): Promise<void>;
  signOut(): Promise<void>;
  resetPassword(email: string): Promise<void>;
  isAdmin(uid: string): Promise<boolean>;
  ownerClaimed(): Promise<boolean>;
  claimSuperAdmin(uid: string): Promise<void>;
  accounts(): Promise<Account[]>;
  account(uid: string): Promise<Account | null>;
  /** Approve a pending registration: assigns IDs, moves requested phones into approved ones, sets plan/fee/expiry. */
  approve(uid: string, plan: PlanId, feeMinor: number, expiresAt: Date | null): Promise<void>;
  patchAccount(uid: string, patch: AccountPatch): Promise<void>;
  setStatus(uid: string, status: Status, message: string): Promise<void>;
  /** Sets a new sign-in PIN (4-8 digits) for the restaurant's owner. The app applies it the moment it sees it; nothing on the phone is cleared. */
  resetOwnerPin(uid: string, pin: string): Promise<void>;
  approvePhone(uid: string, phoneId: string): Promise<void>;
  removePhone(uid: string, phoneId: string): Promise<void>;
  notes(uid: string): Promise<string>;
  setNotes(uid: string, text: string): Promise<void>;
  days(uid: string): Promise<DayTotal[]>;
  devices(): Promise<Device[]>;
  setDeviceBlocked(uid: string, phoneId: string, blocked: boolean): Promise<void>;
  deleteDevice(id: string): Promise<void>;
  invoices(): Promise<Invoice[]>;
  invoice(id: string): Promise<Invoice | null>;
  createInvoice(uid: string, amountMinor: number, discountMinor: number, dueAt: Date, plan: PlanId | null): Promise<Invoice>;
  recordPayment(invoiceId: string): Promise<void>;
  voidInvoice(invoiceId: string): Promise<void>;
  verifyInvoice(token: string): Promise<{ number: string; businessName: string; amountMinor: number; currency: string; status: string; issuedAt: Date } | null>;
  threads(): Promise<Thread[]>;
  messages(uid: string): Promise<Message[]>;
  sendMessage(uid: string, text: string): Promise<void>;
  markRead(uid: string): Promise<void>;
  clearChat(uid: string): Promise<void>;
  deleteChat(uid: string): Promise<void>;
  getBranding(): Promise<Branding>; setBranding(b: Branding): Promise<void>;
  getAppControl(): Promise<AppControl>; setAppControl(a: AppControl): Promise<void>;
  getBilling(): Promise<Billing>; setBilling(b: Billing): Promise<void>;
  admins(): Promise<AdminUser[]>;
  /** With a UID, adds that existing login; with email + password, creates the login first. Returns the UID. */
  addAdmin(a: NewAdmin): Promise<string>;
  setAdminPerms(uid: string, perms: string[]): Promise<void>;
  removeAdmin(uid: string): Promise<void>;
  /** What the signed-in admin may open. */
  myAccess(uid: string): Promise<{ owner: boolean; perms: string[] | null }>;
  auditLog(): Promise<AuditEntry[]>;
  /** Deletes the chosen entries (and records that in the log). */
  deleteAudit(ids: string[]): Promise<void>;
  /** Deletes every entry older than the given number of days; returns how many. */
  cleanAudit(olderThanDays: number): Promise<number>;
  notices(): Promise<Notice[]>;
  sendNotice(n: { title: string; body: string; kind: string; target: string }): Promise<void>;
  deleteNotice(id: string): Promise<void>;
}
