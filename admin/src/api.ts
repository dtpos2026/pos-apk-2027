// The panel talks to the backend only through this interface. SupabaseApi is the real one;
// tests inject a hand-written fake (never shipped in the production bundle path).
export interface Business { id: string; name: string; owner_name: string; phone: string; email: string | null; country: string; currency: string; status: string; status_note: string | null; created_at: string }
export interface Plan { id: string; name: string; billing: string; price_minor: number; currency: string; modules: string[]; max_devices: number; offline_grace_days: number }
export interface License { id: string; business_id: string; plan_id: string; status: string; modules: string[]; starts_at: string; expires_at: string | null; offline_grace_days: number; version: number; token: string | null }
export interface Invoice { id: string; number: string; business_id: string; kind: string; amount_minor: number; discount_minor: number; currency: string; due_at: string; status: string }
export interface SupportMessage { id: string; thread_id: string; sender: string; body: string; created_at: string }
export interface SupportThread { id: string; business_id: string; last_message_at: string | null }
export interface AuditRow { id: number; at: string; actor_kind: string; action: string; entity: string | null; entity_id: string | null; business_id: string | null }
export interface Dashboard { businesses: Record<string, number>; licenses: Record<string, number>; devices: number; sales_today: number; unpaid_invoices: number }

export interface AdminApi {
  signIn(email: string, password: string): Promise<void>;
  signOut(): Promise<void>;
  /** Role in dtfood.platform_admin, or null when the signed-in user is not Digital Target staff. */
  myRole(): Promise<string | null>;
  dashboard(): Promise<Dashboard>;
  businesses(): Promise<Business[]>;
  setBusinessStatus(id: string, status: string, note: string): Promise<void>;
  plans(): Promise<Plan[]>;
  licenses(): Promise<License[]>;
  issueLicense(businessId: string, planId: string, startsAt: string, expiresAt: string | null): Promise<void>;
  setLicenseStatus(id: string, status: string, note: string): Promise<void>;
  invoices(): Promise<Invoice[]>;
  createInvoice(businessId: string, kind: string, amountMinor: number, discountMinor: number, due: string, instructions: string): Promise<void>;
  recordPayment(invoiceId: string, amountMinor: number, method: string, reference: string): Promise<void>;
  threads(): Promise<SupportThread[]>;
  messages(threadId: string): Promise<SupportMessage[]>;
  sendSupport(businessId: string, body: string): Promise<void>;
  audit(): Promise<AuditRow[]>;
  company(): Promise<Record<string, string>>;
  setCompany(key: string, value: string): Promise<void>;
}
