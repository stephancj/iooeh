"use client";

import { useEffect, useMemo, useState } from "react";
import { Boxes, CircleGauge, Plus, Search, ToggleLeft } from "lucide-react";
import { toast } from "sonner";
import {
  createFeature,
  deactivateFeature,
  FeatureDefinition,
  FeatureValueType,
  getFeatures,
  updateFeature,
} from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type FeatureForm = {
  code: string;
  name: string;
  description: string;
  category: string;
  valueType: FeatureValueType;
  unit: string;
  displayOrder: number;
};

const emptyForm: FeatureForm = {
  code: "",
  name: "",
  description: "",
  category: "Général",
  valueType: "boolean",
  unit: "",
  displayOrder: 0,
};

export default function FeaturesPage() {
  const [features, setFeatures] = useState<FeatureDefinition[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("all");
  const [editing, setEditing] = useState<FeatureDefinition | null>(null);
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState<FeatureForm>(emptyForm);

  const load = () => {
    setLoading(true);
    getFeatures()
      .then((response) => setFeatures(response.data))
      .catch(() => toast.error("Impossible de charger le catalogue."))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  const categories = useMemo(
    () => Array.from(new Set(features.map((feature) => feature.category))).sort(),
    [features],
  );
  const filtered = features.filter((feature) => {
    const query = search.trim().toLowerCase();
    const matches = !query || [feature.name, feature.code, feature.description ?? ""]
      .some((value) => value.toLowerCase().includes(query));
    return matches && (category === "all" || feature.category === category);
  });

  function showCreate() {
    setEditing(null);
    setForm(emptyForm);
    setOpen(true);
  }

  function showEdit(feature: FeatureDefinition) {
    setEditing(feature);
    setForm({
      code: feature.code,
      name: feature.name,
      description: feature.description ?? "",
      category: feature.category,
      valueType: feature.valueType,
      unit: feature.unit ?? "",
      displayOrder: feature.displayOrder,
    });
    setOpen(true);
  }

  async function save() {
    if (!form.name.trim() || (!editing && !form.code.trim())) return;
    setSaving(true);
    const payload = { ...form, unit: form.unit || null, description: form.description || null };
    try {
      if (editing) await updateFeature(editing.id, payload);
      else await createFeature(payload);
      toast.success(editing ? "Fonctionnalité mise à jour" : "Fonctionnalité créée");
      setOpen(false);
      load();
    } catch {
      toast.error("La fonctionnalité n’a pas pu être enregistrée.");
    } finally {
      setSaving(false);
    }
  }

  async function toggle(feature: FeatureDefinition) {
    try {
      if (feature.isActive) await deactivateFeature(feature.id);
      else await updateFeature(feature.id, { isActive: true });
      setFeatures((current) => current.map((item) => item.id === feature.id ? { ...item, isActive: !item.isActive } : item));
    } catch {
      toast.error("Impossible de modifier le statut.");
    }
  }

  return (
    <div className="space-y-6">
      <header className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <div className="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-trackeo-primary">
            <Boxes className="h-4 w-4" /> Catalogue commercial
          </div>
          <h1 className="text-3xl font-bold tracking-tight text-trackeo-dark">Fonctionnalités</h1>
          <p className="mt-1 text-sm text-muted-foreground">La source unique des capacités que les plans peuvent activer ou limiter.</p>
        </div>
        <Button onClick={showCreate} className="gap-2"><Plus className="h-4 w-4" /> Nouvelle fonctionnalité</Button>
      </header>

      <div className="grid gap-3 sm:grid-cols-3">
        <Metric label="Fonctionnalités" value={features.length} icon={Boxes} />
        <Metric label="Actives" value={features.filter((feature) => feature.isActive).length} icon={ToggleLeft} />
        <Metric label="Limites mesurées" value={features.filter((feature) => feature.valueType === "number").length} icon={CircleGauge} />
      </div>

      <section className="overflow-hidden rounded-2xl border bg-card shadow-sm">
        <div className="flex flex-col gap-3 border-b p-4 md:flex-row">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Rechercher par nom, code ou description…" className="pl-9" />
          </div>
          <select value={category} onChange={(event) => setCategory(event.target.value)} className="h-10 rounded-md border bg-background px-3 text-sm">
            <option value="all">Toutes les catégories</option>
            {categories.map((item) => <option key={item} value={item}>{item}</option>)}
          </select>
        </div>

        <div className="divide-y">
          {loading ? <p className="p-8 text-center text-sm text-muted-foreground">Chargement du catalogue…</p> : filtered.map((feature) => (
            <button key={feature.id} onClick={() => showEdit(feature)} className="grid w-full gap-3 p-4 text-left transition-colors hover:bg-muted/40 md:grid-cols-[1fr_180px_130px_110px] md:items-center">
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-semibold">{feature.name}</span>
                  <Badge variant={feature.isActive ? "default" : "secondary"}>{feature.isActive ? "Active" : "Inactive"}</Badge>
                </div>
                <p className="mt-1 truncate text-sm text-muted-foreground">{feature.description || "Sans description"}</p>
                <code className="mt-1 block text-xs text-trackeo-primary-dark/70">{feature.code}</code>
              </div>
              <span className="text-sm text-muted-foreground">{feature.category}</span>
              <Badge variant="outline" className="w-fit">{feature.valueType === "number" ? `Limite${feature.unit ? ` · ${feature.unit}` : ""}` : feature.valueType}</Badge>
              <Button type="button" size="sm" variant="ghost" onClick={(event) => { event.stopPropagation(); void toggle(feature); }}>
                {feature.isActive ? "Désactiver" : "Activer"}
              </Button>
            </button>
          ))}
          {!loading && filtered.length === 0 && <p className="p-10 text-center text-sm text-muted-foreground">Aucune fonctionnalité ne correspond à cette recherche.</p>}
        </div>
      </section>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-xl">
          <DialogHeader><DialogTitle>{editing ? "Modifier la fonctionnalité" : "Créer une fonctionnalité"}</DialogTitle></DialogHeader>
          <div className="grid gap-4 py-2 sm:grid-cols-2">
            <Field label="Nom"><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field>
            <Field label="Code immuable"><Input disabled={!!editing} value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} placeholder="ex. history_retention_days" /></Field>
            <Field label="Catégorie"><Input value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })} /></Field>
            <Field label="Type de valeur">
              <select value={form.valueType} onChange={(e) => setForm({ ...form, valueType: e.target.value as FeatureValueType })} className="h-10 w-full rounded-md border bg-background px-3 text-sm">
                <option value="boolean">Activation oui/non</option><option value="number">Limite numérique</option><option value="string">Valeur texte</option>
              </select>
            </Field>
            <Field label="Unité"><Input value={form.unit} onChange={(e) => setForm({ ...form, unit: e.target.value })} placeholder="jours, véhicules…" /></Field>
            <Field label="Ordre"><Input type="number" value={form.displayOrder} onChange={(e) => setForm({ ...form, displayOrder: Number(e.target.value) })} /></Field>
            <div className="sm:col-span-2"><Field label="Description"><textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} className="min-h-24 w-full rounded-md border bg-background p-3 text-sm" /></Field></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setOpen(false)}>Annuler</Button><Button onClick={save} disabled={saving}>{saving ? "Enregistrement…" : "Enregistrer"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function Metric({ label, value, icon: Icon }: { label: string; value: number; icon: typeof Boxes }) {
  return <div className="rounded-2xl border bg-card p-4"><div className="flex items-center justify-between"><span className="text-sm text-muted-foreground">{label}</span><Icon className="h-4 w-4 text-trackeo-primary" /></div><strong className="mt-2 block text-2xl text-trackeo-dark">{value}</strong></div>;
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="space-y-1.5"><Label>{label}</Label>{children}</div>;
}
