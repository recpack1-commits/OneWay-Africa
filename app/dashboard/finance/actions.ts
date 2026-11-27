"use server";

import { createHash, randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { requireAnyPermission, requirePermission } from "@/lib/authorization";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { Json } from "@/lib/supabase/database.types";

export type FinanceActionState = {
  error?: string;
  message?: string;
  success?: boolean;
};

const MAX_RECEIPT_BYTES = 5_000_000;
const MAX_EXPENSE_LINES = 100;
const MAX_MONEY = 999_999_999_999.99;
const financePath = "/dashboard/finance";
const allowedReceipts = {
  "image/jpeg": ["jpg", "jpeg"],
  "image/png": ["png"],
  "image/webp": ["webp"],
  "application/pdf": ["pdf"],
} as const;

function formString(data: FormData, key: string) {
  const value = data.get(key);
  return typeof value === "string" ? value.trim() : "";
}

function validUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function validDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().slice(0, 10) === value;
}

function positiveAmount(value: string) {
  if (!/^\d+(?:\.\d{1,2})?$/.test(value)) return null;
  const amount = Number(value);
  return Number.isFinite(amount) && amount > 0 && amount <= MAX_MONEY && Math.round(amount * 100) === amount * 100
    ? amount
    : null;
}

function currencyAndRate(data: FormData) {
  const currency = formString(data, "currency").toUpperCase();
  const rateText = formString(data, "exchangeRate");
  if (currency === "GHS" && !rateText) {
    return { currency, rate: 1, rateDate: null, rateSource: null };
  }
  if (!/^\d+(?:\.\d{1,8})?$/.test(rateText)) return null;
  const rate = Number(rateText);
  const rateDate = formString(data, "exchangeRateDate");
  const rateSource = formString(data, "exchangeRateSource");
  if (!/^[A-Z]{3}$/.test(currency) || !Number.isFinite(rate) || rate <= 0 || rate > 9_999_999_999.99999999) return null;
  if (currency === "GHS") {
    if (rate !== 1) return null;
    return { currency, rate, rateDate: null, rateSource: null };
  }
  if (!validDate(rateDate) || !rateSource || rateSource.length > 500) return null;
  return { currency, rate, rateDate, rateSource };
}

function parseLines(value: string): Array<{
  line_number: number;
  expense_category_id: string;
  description: string;
  amount: number;
}> | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(value);
  } catch {
    return null;
  }
  if (!Array.isArray(parsed) || parsed.length === 0 || parsed.length > MAX_EXPENSE_LINES) return null;
  const lines = parsed.map((item, index) => {
    if (!item || typeof item !== "object") return null;
    const row = item as Record<string, unknown>;
    const amount = typeof row.amount === "number" ? row.amount : Number(row.amount);
    if (
      typeof row.expense_category_id !== "string"
      || !validUuid(row.expense_category_id)
      || typeof row.description !== "string"
      || !row.description.trim()
      || row.description.trim().length > 500
      || !Number.isFinite(amount)
      || amount <= 0
      || amount > MAX_MONEY
      || Math.round(amount * 100) !== amount * 100
    ) return null;
    return {
      line_number: index + 1,
      expense_category_id: row.expense_category_id,
      description: row.description.trim(),
      amount,
    };
  });
  const validLines = lines.filter(
    (line): line is NonNullable<(typeof lines)[number]> => line !== null,
  );
  return validLines.length === lines.length ? validLines : null;
}

function actionError(error: { code?: string; message?: string }) {
  const message = error.message?.toLowerCase() ?? "";
  if (error.code === "42501") return { error: "You are not authorized for this finance action." };
  if (message.includes("idempotency key") || message.includes("idempotency")) {
    return { error: "This retry key was already used with different details. Start a new operation." };
  }
  if (error.code === "23514") {
    return { error: error.message || "The finance request does not meet the approved policy." };
  }
  if (error.code === "23505") return { error: "This finance record already exists or conflicts with another request." };
  return { error: "The finance operation could not be completed. Please retry." };
}

function revalidateFinance() {
  revalidatePath(financePath);
  revalidatePath("/dashboard");
}

export async function createExpenseAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  await requirePermission("financial.expenses.own_manage");
  const periodId = formString(formData, "reportingPeriodId");
  const expenseDate = formString(formData, "expenseDate");
  const description = formString(formData, "description");
  const lines = parseLines(formString(formData, "lines"));
  const currency = currencyAndRate(formData);
  const clientSubmissionId = formString(formData, "clientSubmissionId");
  if (
    !validUuid(periodId)
    || !validDate(expenseDate)
    || !description
    || description.length > 2000
    || !lines
    || !currency
    || !validUuid(clientSubmissionId)
  ) return { error: "Complete the expense details, FX fields, item lines, and retry key." };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("create_own_financial_expense", {
    p_reporting_period_id: periodId,
    p_expense_date: expenseDate,
    p_currency: currency.currency,
    p_exchange_rate_to_ghs: currency.rate,
    p_exchange_rate_date: currency.rateDate,
    p_exchange_rate_source: currency.rateSource,
    p_description: description,
    p_lines: lines as Json,
    p_client_submission_id: clientSubmissionId,
  });
  if (error) return actionError(error);
  revalidateFinance();
  return { success: true, message: "Expense draft saved. Add at least one receipt before submitting." };
}

export async function updateExpenseAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  await requirePermission("financial.expenses.own_manage");
  const expenseId = formString(formData, "expenseId");
  const periodId = formString(formData, "reportingPeriodId");
  const expenseDate = formString(formData, "expenseDate");
  const description = formString(formData, "description");
  const lines = parseLines(formString(formData, "lines"));
  const currency = currencyAndRate(formData);
  const clientSubmissionId = formString(formData, "clientSubmissionId");
  if (
    !validUuid(expenseId)
    || !validUuid(periodId)
    || !validDate(expenseDate)
    || !description
    || description.length > 2000
    || !lines
    || !currency
    || !validUuid(clientSubmissionId)
  ) return { error: "Complete the expense details, FX fields, item lines, and retry key." };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("update_own_financial_expense", {
    p_expense_id: expenseId,
    p_reporting_period_id: periodId,
    p_expense_date: expenseDate,
    p_currency: currency.currency,
    p_exchange_rate_to_ghs: currency.rate,
    p_exchange_rate_date: currency.rateDate,
    p_exchange_rate_source: currency.rateSource,
    p_description: description,
    p_lines: lines as Json,
    p_client_submission_id: clientSubmissionId,
  });
  if (error) return actionError(error);
  revalidateFinance();
  return { success: true, message: "Expense draft updated." };
}

export async function submitExpenseAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  await requirePermission("financial.expenses.own_manage");
  const expenseId = formString(formData, "expenseId");
  const note = formString(formData, "overFundsNote");
  if (!validUuid(expenseId) || note.length > 1000) return { error: "Select a valid expense." };
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("submit_own_financial_expense", {
    p_expense_id: expenseId,
    p_over_funds_note: note || null,
  });
  if (error) return actionError(error);
  revalidateFinance();
  return { success: true, message: "Expense submitted for Financial Director review." };
}

export async function cancelExpenseAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  await requirePermission("financial.expenses.own_manage");
  const expenseId = formString(formData, "expenseId");
  if (!validUuid(expenseId)) return { error: "Select a valid expense." };
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("cancel_own_financial_expense", { p_expense_id: expenseId });
  if (error) return actionError(error);
  revalidateFinance();
  return { success: true, message: "Expense cancelled." };
}

export async function reviewExpenseAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  await requirePermission("financial.manage");
  const expenseId = formString(formData, "expenseId");
  const decision = formString(formData, "decision");
  const comments = formString(formData, "comments");
  if (!validUuid(expenseId) || !["approve", "query", "reject"].includes(decision) || comments.length > 2000) {
    return { error: "Select a valid review decision and provide any required comments." };
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("review_financial_expense", {
    p_expense_id: expenseId,
    p_decision: decision,
    p_comments: comments || null,
  });
  if (error) return actionError(error);
  revalidateFinance();
  return { success: true, message: "Expense review saved." };
}

export async function createDisbursementAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  await requirePermission("financial.disbursements.create");
  const reference = formString(formData, "reference");
  const missionaryId = formString(formData, "missionaryId");
  const periodId = formString(formData, "reportingPeriodId");
  const amount = positiveAmount(formString(formData, "amountSent"));
  const sentDate = formString(formData, "sentDate");
  const paymentMethod = formString(formData, "paymentMethod");
  const transactionReference = formString(formData, "transactionReference");
  const notes = formString(formData, "notes");
  const currency = currencyAndRate(formData);
  const clientSubmissionId = formString(formData, "clientSubmissionId");
  if (
    !reference || reference.length > 100
    || !validUuid(missionaryId) || !validUuid(periodId) || !amount
    || !validDate(sentDate) || !paymentMethod || paymentMethod.length > 100
    || transactionReference.length > 200 || notes.length > 2000
    || !currency || !validUuid(clientSubmissionId)
  ) return { error: "Complete the disbursement, payee, FX, and retry-key fields." };
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("create_financial_disbursement", {
    p_reference: reference,
    p_missionary_id: missionaryId,
    p_reporting_period_id: periodId,
    p_amount_sent: amount,
    p_currency: currency.currency,
    p_sent_date: sentDate,
    p_payment_method: paymentMethod,
    p_transaction_reference: transactionReference || null,
    p_notes: notes || null,
    p_exchange_rate_to_ghs: currency.rate,
    p_exchange_rate_date: currency.rateDate,
    p_exchange_rate_source: currency.rateSource,
    p_client_submission_id: clientSubmissionId,
  });
  if (error) return actionError(error);
  revalidateFinance();
  return { success: true, message: "Disbursement recorded." };
}

export async function confirmDisbursementAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  await requirePermission("financial.disbursements.own_confirm");
  const disbursementId = formString(formData, "disbursementId");
  const decision = formString(formData, "decision");
  const notes = formString(formData, "notes");
  const clientSubmissionId = formString(formData, "clientSubmissionId");
  const amount = formString(formData, "amountReceived");
  const amountReceived = decision === "confirm" ? positiveAmount(amount) : null;
  const receivedDate = formString(formData, "receivedDate");
  const amountMode = formString(formData, "amountMode");
  if (
    !validUuid(disbursementId) || !["confirm", "dispute"].includes(decision)
    || !validUuid(clientSubmissionId) || notes.length > 2000
    || (decision === "confirm" && (!amountReceived || !validDate(receivedDate) || !["incremental", "cumulative"].includes(amountMode)))
    || (decision === "dispute" && !notes)
  ) return { error: "Enter a valid confirmation or dispute with the required details." };
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("record_own_disbursement_confirmation", {
    p_disbursement_id: disbursementId,
    p_decision: decision,
    p_amount_received: amountReceived,
    p_received_date: decision === "confirm" ? receivedDate : null,
    p_amount_mode: decision === "confirm" ? amountMode : null,
    p_notes: notes || null,
    p_client_submission_id: clientSubmissionId,
  });
  if (error) return actionError(error);
  revalidateFinance();
  return { success: true, message: decision === "dispute" ? "Dispute recorded." : "Receipt confirmation recorded." };
}

export async function resolveDisbursementAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  await requirePermission("financial.manage");
  const disbursementId = formString(formData, "disbursementId");
  const resolutionType = formString(formData, "resolutionType");
  const notes = formString(formData, "notes");
  const adjustmentId = formString(formData, "financialAdjustmentId");
  if (
    !validUuid(disbursementId)
    || !["resolve_dispute", "settle_short", "reconcile_overpayment"].includes(resolutionType)
    || !notes || notes.length > 2000
    || (resolutionType === "reconcile_overpayment" && !validUuid(adjustmentId))
  ) return { error: "Enter a valid Financial Director resolution and note." };
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("resolve_financial_disbursement", {
    p_disbursement_id: disbursementId,
    p_resolution_type: resolutionType,
    p_notes: notes,
    p_financial_adjustment_id: adjustmentId || null,
  });
  if (error) return actionError(error);
  revalidateFinance();
  return { success: true, message: "Disbursement resolution saved." };
}

export async function createAdjustmentAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  await requirePermission("financial.manage");
  const periodId = formString(formData, "reportingPeriodId");
  const targetType = formString(formData, "targetType");
  const targetId = formString(formData, "targetId");
  const adjustmentType = formString(formData, "adjustmentType");
  const amountText = formString(formData, "amount");
  const amount = Number(amountText);
  const currency = currencyAndRate(formData);
  const reason = formString(formData, "reason");
  const adjustmentDate = formString(formData, "adjustmentDate");
  const clientSubmissionId = formString(formData, "clientSubmissionId");
  const reversalOfId = formString(formData, "reversalOfId");
  const expenseId = targetType === "expense" ? targetId : "";
  const disbursementId = targetType === "disbursement" ? targetId : "";
  if (
    !validUuid(periodId) || !validUuid(targetId) || !currency || !Number.isFinite(amount)
    || !/^-?\d+(?:\.\d{1,2})?$/.test(amountText)
    || amount === 0 || Math.abs(amount) > MAX_MONEY || Math.round(amount * 100) !== amount * 100
    || !reason || reason.length > 2000 || !validDate(adjustmentDate)
    || !validUuid(clientSubmissionId)
    || (reversalOfId && !validUuid(reversalOfId))
    || !["correction", "reimbursement", "reversal", "carry_forward", "other"].includes(adjustmentType)
    || !["expense", "disbursement"].includes(targetType)
  ) return { error: "Complete all adjustment details, including the target and retry key." };
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("create_financial_adjustment", {
    p_reporting_period_id: periodId,
    p_disbursement_id: disbursementId || null,
    p_expense_id: expenseId || null,
    p_adjustment_type: adjustmentType,
    p_amount: amount,
    p_currency: currency.currency,
    p_reason: reason,
    p_adjustment_date: adjustmentDate,
    p_exchange_rate_to_ghs: currency.rate,
    p_exchange_rate_date: currency.rateDate,
    p_exchange_rate_source: currency.rateSource,
    p_client_submission_id: clientSubmissionId,
    p_reversal_of_id: reversalOfId || null,
  });
  if (error) return actionError(error);
  revalidateFinance();
  return { success: true, message: "Adjustment submitted for independent review." };
}

export async function approveAdjustmentAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  const authorization = await requirePermission("financial.manage");
  const adjustmentId = formString(formData, "adjustmentId");
  if (!validUuid(adjustmentId)) return { error: "Select a valid adjustment." };
  const supabase = await createSupabaseServerClient();
  const { data: adjustment, error: readError } = await supabase
    .from("financial_adjustments")
    .select("requested_by")
    .eq("id", adjustmentId)
    .maybeSingle();
  if (readError) return actionError(readError);
  if (!adjustment) return { error: "Adjustment not found." };
  if (adjustment.requested_by === authorization.userId) {
    return { error: "You cannot approve your own adjustment." };
  }
  const { error } = await supabase.rpc("approve_financial_adjustment", {
    p_adjustment_id: adjustmentId,
  });
  if (error) return actionError(error);
  revalidateFinance();
  return { success: true, message: "Adjustment approved." };
}

export async function rejectAdjustmentAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  const authorization = await requirePermission("financial.manage");
  const adjustmentId = formString(formData, "adjustmentId");
  const reason = formString(formData, "reason");
  if (!validUuid(adjustmentId) || !reason || reason.length > 2000) {
    return { error: "Select an adjustment and enter a rejection reason." };
  }
  const supabase = await createSupabaseServerClient();
  const { data: adjustment, error: readError } = await supabase
    .from("financial_adjustments")
    .select("requested_by")
    .eq("id", adjustmentId)
    .maybeSingle();
  if (readError) return actionError(readError);
  if (!adjustment) return { error: "Adjustment not found." };
  if (adjustment.requested_by === authorization.userId) {
    return { error: "You cannot reject your own adjustment." };
  }
  const { error } = await supabase.rpc("reject_financial_adjustment", {
    p_adjustment_id: adjustmentId,
    p_reason: reason,
  });
  if (error) return actionError(error);
  revalidateFinance();
  return { success: true, message: "Adjustment rejected." };
}

function signatureMatches(bytes: Uint8Array, contentType: keyof typeof allowedReceipts) {
  if (contentType === "image/jpeg") return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (contentType === "image/png") {
    return bytes.length >= 8 && [137, 80, 78, 71, 13, 10, 26, 10].every((byte, index) => bytes[index] === byte);
  }
  if (contentType === "image/webp") {
    return bytes.length >= 12
      && String.fromCharCode(...bytes.slice(0, 4)) === "RIFF"
      && String.fromCharCode(...bytes.slice(8, 12)) === "WEBP";
  }
  return bytes.length >= 5 && new TextDecoder().decode(bytes.slice(0, 5)) === "%PDF-";
}

function receiptType(file: File) {
  const filename = file.name.split(/[\\/]/).pop() ?? "";
  const extension = filename.split(".").pop()?.toLowerCase() ?? "";
  const mime = file.type as keyof typeof allowedReceipts;
  const matches = (allowedReceipts as Record<string, readonly string[]>)[mime];
  if (!matches || !matches.includes(extension)) return null;
  if (!file.size || file.size > MAX_RECEIPT_BYTES) return null;
  return { filename, mime };
}

function matchingStoredAsset(
  asset: {
    uploaded_by: string;
    content_type: string;
    size_bytes: number;
    checksum_sha256: string | null;
    original_filename: string;
    upload_status: string;
    content_signature_verified_at: string | null;
    deleted_at: string | null;
  },
  userId: string,
  mime: string,
  size: number,
  checksum: string,
  filename: string,
) {
  return asset.uploaded_by === userId
    && asset.content_type === mime
    && asset.size_bytes === size
    && asset.checksum_sha256 === checksum
    && asset.original_filename === filename.slice(0, 255)
    && asset.upload_status === "uploaded"
    && asset.content_signature_verified_at !== null
    && asset.deleted_at === null;
}

async function uploadAndLinkReceipt(
  formData: FormData,
  kind: "expense" | "disbursement",
): Promise<FinanceActionState> {
  const permission = kind === "expense"
    ? "financial.expenses.own_manage"
    : "financial.disbursements.evidence";
  const authorization = await requirePermission(permission);
  const recordId = formString(formData, kind === "expense" ? "expenseId" : "disbursementId");
  const replacementId = formString(formData, "supersedesReceiptId");
  const clientSubmissionId = formString(formData, "clientSubmissionId");
  const file = formData.get("file");
  if (!validUuid(recordId) || !validUuid(clientSubmissionId) || !(file instanceof File)) {
    return { error: "Choose a valid finance record, file, and retry key." };
  }
  const type = receiptType(file);
  if (!type) return { error: "Upload a file no larger than 5 MB with a matching JPEG, PNG, WebP, or PDF type and extension." };

  const supabase = await createSupabaseServerClient();
  if (kind === "expense") {
    const { data: expense, error } = await supabase
      .from("expenses")
      .select("id,status")
      .eq("id", recordId)
      .maybeSingle();
    if (error) return actionError(error);
    if (!expense || !["draft", "queried"].includes(expense.status)) {
      return { error: "Receipts can only be added to your draft or queried expense." };
    }
  } else {
    const { data: disbursement, error } = await supabase
      .from("disbursements")
      .select("id")
      .eq("id", recordId)
      .eq("created_by", authorization.userId)
      .maybeSingle();
    if (error) return actionError(error);
    if (!disbursement) return { error: "Payment evidence can only be attached to a disbursement you created." };
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  if (!signatureMatches(bytes, type.mime)) return { error: "The file contents do not match the allowed file signature." };

  const admin = createSupabaseAdminClient();
  if (kind === "expense" && replacementId && !validUuid(replacementId)) {
    return { error: "Select a valid receipt to replace." };
  }
  const bucket = "oneway-private";
  const objectPath = `finance/${kind}/${authorization.userId}/${recordId}/${clientSubmissionId}`;
  const localChecksum = createHash("sha256").update(bytes).digest("hex");
  const { data: previousAsset, error: previousAssetError } = await admin
    .from("file_assets")
    .select("id,uploaded_by,content_type,size_bytes,checksum_sha256,upload_status,content_signature_verified_at,deleted_at,original_filename")
    .eq("object_path", objectPath)
    .maybeSingle();
  if (previousAssetError) return { error: "Unable to verify the existing upload retry. Please retry." };
  let existingAsset = previousAsset;
  if (existingAsset && !matchingStoredAsset(
    existingAsset,
    authorization.userId,
    type.mime,
    bytes.byteLength,
    localChecksum,
    type.filename,
  )) return { error: "This retry key was already used with different file contents. Start a new upload." };

  if (!existingAsset) {
    const { error: uploadError } = await admin.storage.from(bucket).upload(objectPath, bytes, {
      contentType: type.mime,
      upsert: false,
    });
    if (uploadError) {
      const { data: assetAfterRetry, error: retryLookupError } = await admin
        .from("file_assets")
        .select("id,content_type,size_bytes,checksum_sha256,upload_status,content_signature_verified_at,deleted_at,original_filename,uploaded_by")
        .eq("object_path", objectPath)
        .maybeSingle();
      if (retryLookupError) return { error: "Unable to verify a concurrent upload retry. Please retry." };
      if (assetAfterRetry) {
        if (!matchingStoredAsset(
          assetAfterRetry,
          authorization.userId,
          type.mime,
          bytes.byteLength,
          localChecksum,
          type.filename,
        )) return { error: "This retry key was already used with different file contents." };
        existingAsset = assetAfterRetry;
      } else {
        const { data: pendingObject, error: pendingDownloadError } = await admin.storage.from(bucket).download(objectPath);
        if (pendingDownloadError || !pendingObject) return { error: "The private finance upload failed. Please retry." };
        const pendingBytes = new Uint8Array(await pendingObject.arrayBuffer());
        if (
          pendingBytes.byteLength !== bytes.byteLength
          || createHash("sha256").update(pendingBytes).digest("hex") !== localChecksum
          || !signatureMatches(pendingBytes, type.mime)
        ) return { error: "The pending upload does not match this retry. Start a new upload." };
      }
    }
  }

  const { data: storedObject, error: downloadError } = await admin.storage.from(bucket).download(objectPath);
  if (downloadError || !storedObject) {
    return { error: "The uploaded file could not be verified from private storage." };
  }
  const storedBytes = new Uint8Array(await storedObject.arrayBuffer());
  const checksum = createHash("sha256").update(storedBytes).digest("hex");
  if (
    storedBytes.byteLength !== bytes.byteLength
    || checksum !== localChecksum
    || !signatureMatches(storedBytes, type.mime)
  ) {
    return { error: "The stored receipt did not pass signature and integrity verification." };
  }

  let assetId = existingAsset?.id;
  if (!assetId) {
    const { data: asset, error: assetError } = await admin
      .from("file_assets")
      .insert({
        bucket_id: bucket,
        object_path: objectPath,
        original_filename: type.filename.slice(0, 255),
        content_type: type.mime,
        size_bytes: storedBytes.byteLength,
        checksum_sha256: checksum,
        upload_status: "uploaded",
        uploaded_by: authorization.userId,
        content_signature_verified_at: new Date().toISOString(),
      })
      .select("id")
      .maybeSingle();
    if (assetError || !asset) {
      const { data: concurrentAsset, error: concurrentError } = await admin
        .from("file_assets")
        .select("id,content_type,size_bytes,checksum_sha256,upload_status,content_signature_verified_at,deleted_at,original_filename,uploaded_by")
        .eq("object_path", objectPath)
        .maybeSingle();
      if (
        concurrentError || !concurrentAsset
        || !matchingStoredAsset(
          concurrentAsset,
          authorization.userId,
          type.mime,
          bytes.byteLength,
          checksum,
          type.filename,
        )
      ) return { error: "The verified upload could not be registered. Confirm the Stage 3 migration is applied." };
      assetId = concurrentAsset.id;
    } else {
      assetId = asset.id;
    }
  }

  const { error: linkError } = await supabase.rpc("link_financial_receipt", {
    p_record_type: kind,
    p_record_id: recordId,
    p_file_asset_id: assetId,
    p_supersedes_receipt_id: kind === "expense" ? replacementId || null : null,
    p_client_submission_id: clientSubmissionId,
  });
  if (linkError) {
    if (linkError.code === "23514") {
      const { error: assetCleanupError } = await admin.from("file_assets").delete().eq("id", assetId);
      const { error: storageCleanupError } = await admin.storage.from(bucket).remove([objectPath]);
      if (assetCleanupError || storageCleanupError) {
        console.error("Receipt upload cleanup failed after database validation rejected the link.", {
          assetId,
          assetCleanupError,
          storageCleanupError,
        });
        return { error: "Receipt linking failed and the uploaded file needs administrator cleanup." };
      }
    }
    return actionError(linkError);
  }

  revalidateFinance();
  return { success: true, message: "Verified receipt uploaded and linked." };
}

export async function uploadExpenseReceiptAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  return uploadAndLinkReceipt(formData, "expense");
}

export async function uploadDisbursementEvidenceAction(
  _previous: FinanceActionState,
  formData: FormData,
): Promise<FinanceActionState> {
  return uploadAndLinkReceipt(formData, "disbursement");
}
