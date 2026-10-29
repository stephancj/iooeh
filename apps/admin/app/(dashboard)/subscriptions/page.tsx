"use client";

import { Suspense, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { CalendarClock, CreditCard, Search, ShieldCheck, Users } from "lucide-react";
import { toast } from "sonner";
import { CommercialPlan, getPlans, getSubscriptions, upsertSubscription } from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type SubscriptionStatus = "trial" | "active" | "suspended" | "cancelled";
type SubscriptionRow = {
  userId: number;
  name: string | null;
  email: string;
  phone: string | null;
  isActive: boolean;
  subscription: null | {
    id: string;
    planId: string | null;
    plan: string;
    status: SubscriptionStatus;
    nextBillingDate: string | null;
    trialEndsAt: string | null;
    notes: string | null;
    planDetails: CommercialPlan | null;
  };
};

const statusLabels: Record<SubscriptionStatus, string> = { trial: "Essai", active: "Actif", suspended: "Suspendu", cancelled: "Annulé" };

export default function SubscriptionsPage() {
  return <Suspense fallback={null}><SubscriptionsPageContent /></Suspense>;
}

function SubscriptionsPageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const pageParam = parseInt(searchParams.get("page") || "1", 10);

  const [rows, setRows] = useState<SubscriptionRow[]>([]);
  const [meta, setMeta] = useState({ page: 1, totalPages: 1, total: 0 });
  const [plans, setPlans] = useState<CommercialPlan[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<"all" | SubscriptionStatus>("all");
  const [editing, setEditing] = useState<SubscriptionRow | null>(null);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({ planId: "", status: "trial" as SubscriptionStatus, trialEndsAt: "", nextBillingDate: "", notes: "" });

  const load = async (p = pageParam) => {
    setLoading(true);
    try {
      const [subscriptionResponse, planResponse] = await Promise.all([getSubscriptions(p), getPlans()]);
      setRows(subscriptionResponse.data.data as SubscriptionRow[] || []);
      setMeta(subscriptionResponse.data.meta || { page: 1, totalPages: 1, total: 0 });
      setPlans(planResponse.data.filter((plan) => plan.isActive));
    } catch {
      toast.error("Impossible de charger les abonnements.");
    } finally {
      setLoading(false);
    }
  };
  useEffect(() => { void load(pageParam); }, [pageParam]);

  const filtered = useMemo(() => rows.filter((row) => {
    const q = search.trim().toLowerCase();
    const matchesSearch = !q || [row.name ?? "", row.email, row.phone ?? ""].some((value) => value.toLowerCase().includes(q));
    return matchesSearch && (filter === "all" || row.subscription?.status === filter);
  }), [rows, search, filter]);

  function openEditor(row: SubscriptionRow) {
    setEditing(row);
    setForm({
      planId: row.subscription?.planId ?? plans.find((plan) => plan.code === row.subscription?.plan)?.id ?? plans[0]?.id ?? "",
      status: row.subscription?.status ?? "trial",
      trialEndsAt: toDateInput(row.subscription?.trialEndsAt),
      nextBillingDate: toDateInput(row.subscription?.nextBillingDate),
      notes: row.subscription?.notes ?? "",
    });
  }

  async function save() {
    if (!editing || !form.planId) return;
    setSaving(true);
    try {
      await upsertSubscription(editing.userId, {
        planId: form.planId,
        status: form.status,
        trialEndsAt: form.trialEndsAt ? new Date(`${form.trialEndsAt}T23:59:59`).toISOString() : null,
        nextBillingDate: form.nextBillingDate ? new Date(`${form.nextBillingDate}T12:00:00`).toISOString() : null,
        notes: form.notes || null,
      });
      toast.success("Abonnement mis à jour", { description: "Les nouveaux droits sont immédiatement actifs." });
      setEditing(null);
      await load();
    } catch {
      toast.error("L’abonnement n’a pas pu être enregistré.");
    } finally {
      setSaving(false);
    }
  }

  const activeCount = rows.filter((row) => row.subscription?.status === "active").length;
  const trialCount = rows.filter((row) => row.subscription?.status === "trial").length;
  const suspendedCount = rows.filter((row) => row.subscription?.status === "suspended" || row.subscription?.status === "cancelled").length;

  return <div className="space-y-6">
    <header>
      <div className="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-trackeo-primary"><CreditCard className="h-4 w-4" /> Revenus & accès</div>
      <h1 className="text-3xl font-bold tracking-tight text-trackeo-dark">Abonnements</h1>
      <p className="mt-1 text-sm text-muted-foreground">Attribuez un plan, gérez l’essai et coupez les droits sans désactiver le compte.</p>
    </header>

    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <Metric label="Comptes" value={meta.total} icon={Users} tone="neutral" />
      <Metric label="Actifs" value={activeCount} icon={ShieldCheck} tone="green" />
      <Metric label="En essai" value={trialCount} icon={CalendarClock} tone="blue" />
      <Metric label="Suspendus / annulés" value={suspendedCount} icon={CreditCard} tone="red" />
    </div>

    <section className="overflow-hidden rounded-2xl border bg-card shadow-sm">
      <div className="flex flex-col gap-3 border-b p-4 md:flex-row">
        <div className="relative flex-1"><Search className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" /><Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Rechercher un client…" className="pl-9" /></div>
        <div className="flex flex-wrap gap-2">{(["all", "trial", "active", "suspended", "cancelled"] as const).map((status) => <Button key={status} size="sm" variant={filter === status ? "default" : "outline"} onClick={() => setFilter(status)}>{status === "all" ? "Tous" : statusLabels[status]}</Button>)}</div>
      </div>
      <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="border-b bg-muted/30 text-left text-xs uppercase tracking-wider text-muted-foreground"><th className="px-5 py-3">Client</th><th className="px-5 py-3">Plan</th><th className="px-5 py-3">Statut</th><th className="px-5 py-3">Échéance</th><th className="px-5 py-3"></th></tr></thead><tbody className="divide-y">
        {loading ? <tr><td colSpan={5} className="p-10 text-center text-muted-foreground">Chargement des abonnements…</td></tr> : filtered.map((row) => <tr key={row.userId} className="transition-colors hover:bg-muted/30">
          <td className="px-5 py-4"><div className="font-semibold">{row.name || "Sans nom"}</div><div className="text-xs text-muted-foreground">{row.email}</div></td>
          <td className="px-5 py-4"><div className="font-semibold text-trackeo-dark">{row.subscription?.planDetails?.name ?? row.subscription?.plan ?? "Free"}</div><div className="text-xs text-muted-foreground">{row.subscription?.planDetails ? `${Number(row.subscription.planDetails.priceMonthly).toLocaleString("fr-FR")} ${row.subscription.planDetails.currency}/mois` : "Plan par défaut"}</div></td>
          <td className="px-5 py-4"><StatusBadge status={row.subscription?.status ?? "trial"} /></td>
          <td className="px-5 py-4 text-muted-foreground">{formatDate(row.subscription?.status === "trial" ? row.subscription?.trialEndsAt : row.subscription?.nextBillingDate)}</td>
          <td className="px-5 py-4 text-right"><Button size="sm" variant="outline" onClick={() => openEditor(row)}>Gérer</Button></td>
        </tr>)}
        {!loading && filtered.length === 0 && <tr><td colSpan={5} className="p-10 text-center text-muted-foreground">Aucun abonnement trouvé.</td></tr>}
      </tbody></table></div>

      <div className="flex items-center justify-between p-4 border-t border-border">
        <p className="text-sm text-muted-foreground">
          Affichage de {rows.length} sur {meta.total} abonnements
        </p>
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            disabled={meta.page <= 1}
            onClick={() => router.push(`/subscriptions?page=${meta.page - 1}`)}
          >
            Précédent
          </Button>
          <Button
            variant="outline"
            size="sm"
            disabled={meta.page >= meta.totalPages}
            onClick={() => router.push(`/subscriptions?page=${meta.page + 1}`)}
          >
            Suivant
          </Button>
        </div>
      </div>
    </section>

    <Dialog open={!!editing} onOpenChange={(open) => !open && setEditing(null)}><DialogContent className="sm:max-w-xl"><DialogHeader><DialogTitle>Gérer l’abonnement · {editing?.name || editing?.email}</DialogTitle></DialogHeader><div className="grid gap-4 py-2 sm:grid-cols-2">
      <Field label="Plan"><select value={form.planId} onChange={(e) => setForm({ ...form, planId: e.target.value })} className="h-10 w-full rounded-md border bg-background px-3 text-sm">{plans.map((plan) => <option key={plan.id} value={plan.id}>{plan.name} · {Number(plan.priceMonthly).toLocaleString("fr-FR")} {plan.currency}</option>)}</select></Field>
      <Field label="Statut"><select value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value as SubscriptionStatus })} className="h-10 w-full rounded-md border bg-background px-3 text-sm">{Object.entries(statusLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></Field>
      <Field label="Fin de l’essai"><Input type="date" value={form.trialEndsAt} onChange={(e) => setForm({ ...form, trialEndsAt: e.target.value })} /></Field>
      <Field label="Prochaine échéance"><Input type="date" value={form.nextBillingDate} onChange={(e) => setForm({ ...form, nextBillingDate: e.target.value })} /></Field>
      <div className="sm:col-span-2"><Field label="Notes internes"><textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} className="min-h-24 w-full rounded-md border bg-background p-3 text-sm" placeholder="Contexte commercial, paiement manuel…" /></Field></div>
    </div><DialogFooter><Button variant="outline" onClick={() => setEditing(null)}>Annuler</Button><Button onClick={save} disabled={saving}>{saving ? "Enregistrement…" : "Appliquer les droits"}</Button></DialogFooter></DialogContent></Dialog>
  </div>;
}

function Metric({ label, value, icon: Icon, tone }: { label: string; value: number; icon: typeof Users; tone: "neutral" | "green" | "blue" | "red" }) {
  const styles = { neutral: "bg-muted text-foreground", green: "bg-trackeo-pastel-green text-emerald-700", blue: "bg-trackeo-pastel-blue text-blue-700", red: "bg-trackeo-pastel-red text-red-700" };
  return <div className="rounded-2xl border bg-card p-4"><div className="flex items-center justify-between"><span className="text-sm text-muted-foreground">{label}</span><span className={`rounded-lg p-2 ${styles[tone]}`}><Icon className="h-4 w-4" /></span></div><strong className="mt-2 block text-2xl text-trackeo-dark">{value}</strong></div>;
}
function StatusBadge({ status }: { status: SubscriptionStatus }) { const variant = status === "active" ? "default" : status === "trial" ? "secondary" : status === "suspended" ? "destructive" : "outline"; return <Badge variant={variant}>{statusLabels[status]}</Badge>; }
function Field({ label, children }: { label: string; children: React.ReactNode }) { return <div className="space-y-1.5"><Label>{label}</Label>{children}</div>; }
function toDateInput(value?: string | null) { return value ? new Date(value).toISOString().slice(0, 10) : ""; }
function formatDate(value?: string | null) { return value ? new Date(value).toLocaleDateString("fr-FR") : "—"; }
