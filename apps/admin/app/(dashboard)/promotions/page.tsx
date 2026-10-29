"use client";

import { useEffect, useState } from "react";
import { getCoupons, createCoupon, deleteCoupon, getPlans, CommercialPlan } from "@/lib/api";
import { Tag, Plus, Trash2, Gift, Percent, Calendar, CheckCircle, AlertCircle } from "lucide-react";
import { Button } from "@/components/ui/button";

export interface CouponData {
  id: string;
  code: string;
  rewardType: "FREE_PLAN_GIFT" | "FREE_SUBSCRIPTION_DAYS" | "PERCENTAGE_DISCOUNT" | "FIXED_DISCOUNT" | "VEHICLE_QUOTA_BONUS";
  rewardValue: string;
  grantedPlanId: string | null;
  targetPlanId: string | null;
  maxRedemptions: number | null;
  redemptionsCount: number;
  expiresAt: string | null;
  isActive: boolean;
  createdAt: string;
}

export default function PromotionsPage() {
  const [coupons, setCoupons] = useState<CouponData[]>([]);
  const [plans, setPlans] = useState<CommercialPlan[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Form State
  const [code, setCode] = useState("");
  const [rewardType, setRewardType] = useState<CouponData["rewardType"]>("PERCENTAGE_DISCOUNT");
  const [rewardValue, setRewardValue] = useState("20");
  const [grantedPlanId, setGrantedPlanId] = useState("");
  const [targetPlanId, setTargetPlanId] = useState("");
  const [maxRedemptions, setMaxRedemptions] = useState("");
  const [expiresAt, setExpiresAt] = useState("");

  useEffect(() => {
    fetchData();
  }, []);

  async function fetchData() {
    setLoading(true);
    try {
      const [resCoupons, resPlans] = await Promise.all([getCoupons(), getPlans()]);
      setCoupons(resCoupons.data as CouponData[]);
      setPlans(resPlans.data);
    } catch {
      setError("Erreur de chargement des coupons.");
    } finally {
      setLoading(false);
    }
  }

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    try {
      await createCoupon({
        code: code.trim().toUpperCase(),
        rewardType,
        rewardValue: parseFloat(rewardValue) || 0,
        grantedPlanId: rewardType === "FREE_PLAN_GIFT" && grantedPlanId ? grantedPlanId : undefined,
        targetPlanId: (rewardType === "PERCENTAGE_DISCOUNT" || rewardType === "FIXED_DISCOUNT") && targetPlanId ? targetPlanId : undefined,
        maxRedemptions: maxRedemptions ? parseInt(maxRedemptions, 10) : undefined,
        expiresAt: expiresAt ? new Date(expiresAt).toISOString() : undefined,
      });

      setShowModal(false);
      resetForm();
      fetchData();
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      setError(msg || "Erreur lors de la création du coupon.");
    }
  }

  async function handleDelete(id: string) {
    if (!confirm("Voulez-vous vraiment supprimer ce coupon ?")) return;
    try {
      await deleteCoupon(id);
      fetchData();
    } catch {
      setError("Erreur lors de la suppression.");
    }
  }

  function resetForm() {
    setCode("");
    setRewardType("PERCENTAGE_DISCOUNT");
    setRewardValue("20");
    setGrantedPlanId("");
    setTargetPlanId("");
    setMaxRedemptions("");
    setExpiresAt("");
  }

  function getRewardTypeLabel(type: CouponData["rewardType"]) {
    switch (type) {
      case "FREE_PLAN_GIFT": return "Plan Offert";
      case "FREE_SUBSCRIPTION_DAYS": return "Jours d'Abonnement Offerts";
      case "PERCENTAGE_DISCOUNT": return "Réduction Pourcentage (%)";
      case "FIXED_DISCOUNT": return "Réduction Fixe (MGA)";
      case "VEHICLE_QUOTA_BONUS": return "Bonus Quota Véhicules";
    }
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-foreground">Promotions & Codes Coupons</h1>
          <p className="text-sm text-muted-foreground">
            Gérez les codes promo et découvrez le moteur de remboursement dynamique (Dynamic Redeem Engine).
          </p>
        </div>
        <Button onClick={() => setShowModal(true)} className="gap-2 bg-trackeo-primary hover:bg-trackeo-primary/90">
          <Plus className="h-4 w-4" /> Nouveau Coupon
        </Button>
      </div>

      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700 flex items-center gap-2">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}

      {/* Coupons Table */}
      <div className="rounded-xl border bg-card shadow-sm overflow-hidden">
        <div className="p-4 border-b bg-muted/40 flex items-center justify-between">
          <h2 className="text-base font-semibold flex items-center gap-2">
            <Tag className="h-4 w-4 text-trackeo-primary" />
            Liste des Coupons ({coupons.length})
          </h2>
        </div>

        {loading ? (
          <div className="p-8 text-center text-sm text-muted-foreground">Chargement des coupons...</div>
        ) : coupons.length === 0 ? (
          <div className="p-8 text-center text-sm text-muted-foreground">
            Aucun coupon créé pour le moment. Cliquez sur "Nouveau Coupon" pour en créer un.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="border-b bg-muted/20 text-xs font-semibold text-muted-foreground uppercase">
                <tr>
                  <th className="px-4 py-3">Code</th>
                  <th className="px-4 py-3">Type Récompense</th>
                  <th className="px-4 py-3">Valeur</th>
                  <th className="px-4 py-3">Cible / Offert</th>
                  <th className="px-4 py-3">Utilisations</th>
                  <th className="px-4 py-3">Expiration</th>
                  <th className="px-4 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {coupons.map((c) => {
                  const targetPlan = plans.find((p) => p.id === (c.grantedPlanId || c.targetPlanId));
                  return (
                    <tr key={c.id} className="hover:bg-muted/10">
                      <td className="px-4 py-3 font-mono font-bold text-trackeo-primary">{c.code}</td>
                      <td className="px-4 py-3">
                        <span className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium bg-primary/10 text-primary">
                          <Gift className="h-3 w-3" />
                          {getRewardTypeLabel(c.rewardType)}
                        </span>
                      </td>
                      <td className="px-4 py-3 font-medium">
                        {c.rewardType === "PERCENTAGE_DISCOUNT" ? `-${c.rewardValue}%` :
                         c.rewardType === "FIXED_DISCOUNT" ? `-${Number(c.rewardValue).toLocaleString()} MGA` :
                         c.rewardType === "FREE_SUBSCRIPTION_DAYS" ? `+${c.rewardValue} Jours` :
                         c.rewardType === "VEHICLE_QUOTA_BONUS" ? `+${c.rewardValue} Véhicules` :
                         `${c.rewardValue} Jours`}
                      </td>
                      <td className="px-4 py-3 text-muted-foreground">
                        {targetPlan ? targetPlan.name : "Tous les plans"}
                      </td>
                      <td className="px-4 py-3">
                        <span className="font-semibold text-foreground">{c.redemptionsCount}</span>
                        {c.maxRedemptions != null ? ` / ${c.maxRedemptions}` : " (Illimité)"}
                      </td>
                      <td className="px-4 py-3 text-xs text-muted-foreground">
                        {c.expiresAt ? new Date(c.expiresAt).toLocaleDateString() : "Aucune"}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <Button variant="ghost" size="sm" onClick={() => handleDelete(c.id)} className="text-red-600 hover:text-red-700 hover:bg-red-50">
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Modal Création Coupon */}
      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="w-full max-w-lg rounded-xl bg-card p-6 shadow-xl border space-y-4">
            <h3 className="text-lg font-bold">Créer un nouveau Coupon</h3>
            <form onSubmit={handleCreate} className="space-y-4 text-sm">
              <div>
                <label className="block font-medium mb-1">Code Coupon (Ex: WELCOME20)</label>
                <input
                  type="text"
                  required
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  className="w-full rounded-lg border px-3 py-2 uppercase font-mono"
                  placeholder="EX: TESTPREMIUM30"
                />
              </div>

              <div>
                <label className="block font-medium mb-1">Type de Récompense (Dynamic Redeem)</label>
                <select
                  value={rewardType}
                  onChange={(e) => setRewardType(e.target.value as CouponData["rewardType"])}
                  className="w-full rounded-lg border px-3 py-2"
                >
                  <option value="PERCENTAGE_DISCOUNT">Réduction en Pourcentage (%)</option>
                  <option value="FIXED_DISCOUNT">Réduction en Montant Fixe (MGA)</option>
                  <option value="FREE_PLAN_GIFT">Plan Offert pour une Durée (Free Plan Gift)</option>
                  <option value="FREE_SUBSCRIPTION_DAYS">Extension Durée Abonnement Actuel (Jours)</option>
                </select>
              </div>

              <div>
                <label className="block font-medium mb-1">
                  {rewardType === "PERCENTAGE_DISCOUNT" ? "Valeur du Pourcentage (%)" :
                   rewardType === "FIXED_DISCOUNT" ? "Montant de Réduction (MGA)" :
                   rewardType === "VEHICLE_QUOTA_BONUS" ? "Nombre de Véhicules Bonus" :
                   "Durée Offerte (Jours)"}
                </label>
                <input
                  type="number"
                  required
                  min="1"
                  value={rewardValue}
                  onChange={(e) => setRewardValue(e.target.value)}
                  className="w-full rounded-lg border px-3 py-2"
                />
              </div>

              {rewardType === "FREE_PLAN_GIFT" && (
                <div>
                  <label className="block font-medium mb-1">Plan Offert Spécifique</label>
                  <select
                    value={grantedPlanId}
                    onChange={(e) => setGrantedPlanId(e.target.value)}
                    className="w-full rounded-lg border px-3 py-2"
                  >
                    <option value="">-- Sélectionner un Plan --</option>
                    {plans.map((p) => (
                      <option key={p.id} value={p.id}>{p.name} ({p.priceMonthly} MGA)</option>
                    ))}
                  </select>
                </div>
              )}

              {(rewardType === "PERCENTAGE_DISCOUNT" || rewardType === "FIXED_DISCOUNT") && (
                <div>
                  <label className="block font-medium mb-1">Plan Requis Spécifique (Optionnel)</label>
                  <select
                    value={targetPlanId}
                    onChange={(e) => setTargetPlanId(e.target.value)}
                    className="w-full rounded-lg border px-3 py-2"
                  >
                    <option value="">Tous les plans payants</option>
                    {plans.map((p) => (
                      <option key={p.id} value={p.id}>{p.name}</option>
                    ))}
                  </select>
                </div>
              )}

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block font-medium mb-1">Max Utilisations Globales</label>
                  <input
                    type="number"
                    placeholder="Illimité si vide"
                    value={maxRedemptions}
                    onChange={(e) => setMaxRedemptions(e.target.value)}
                    className="w-full rounded-lg border px-3 py-2"
                  />
                </div>
                <div>
                  <label className="block font-medium mb-1">Date d'Expiration</label>
                  <input
                    type="date"
                    value={expiresAt}
                    onChange={(e) => setExpiresAt(e.target.value)}
                    className="w-full rounded-lg border px-3 py-2"
                  />
                </div>
              </div>

              <div className="flex justify-end gap-2 pt-4 border-t">
                <Button type="button" variant="outline" onClick={() => setShowModal(false)}>Annuler</Button>
                <Button type="submit" className="bg-trackeo-primary hover:bg-trackeo-primary/90">Créer Coupon</Button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
