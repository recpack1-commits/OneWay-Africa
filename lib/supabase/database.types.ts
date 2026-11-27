export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

type TableDefinition<Row, Insert = Partial<Row>, Update = Partial<Row>> = {
  Row: Row;
  Insert: Insert;
  Update: Update;
  Relationships: [];
};

type ExpenseRow = {
  id: string;
  missionary_id: string;
  reporting_period_id: string;
  expense_category_id: string | null;
  expense_date: string;
  amount: number;
  currency: string;
  exchange_rate_to_ghs: number | null;
  exchange_rate_date: string | null;
  exchange_rate_source: string | null;
  description: string;
  status: "draft" | "submitted" | "queried" | "approved" | "rejected" | "cancelled";
  submitted_at: string | null;
  created_by: string;
  client_submission_id: string | null;
  submission_payload: Json | null;
  over_funds_flag: boolean;
  over_funds_note: string | null;
  created_at: string;
  updated_at: string;
};

type DisbursementRow = {
  id: string;
  reference: string;
  missionary_id: string;
  reporting_period_id: string;
  amount_sent: number;
  currency: string;
  sent_date: string;
  payment_method: string;
  transaction_reference: string | null;
  status:
    | "awaiting_confirmation"
    | "partially_confirmed"
    | "confirmed"
    | "disputed"
    | "settled_short"
    | "reconciliation_required"
    | "cancelled";
  amount_received: number | null;
  effective_amount_received: number | null;
  received_date: string | null;
  confirmation_notes: string | null;
  exchange_rate_to_ghs: number | null;
  exchange_rate_date: string | null;
  exchange_rate_source: string | null;
  settlement_note: string | null;
  settled_short_approved_by: string | null;
  settled_short_approved_at: string | null;
  notes: string | null;
  created_by: string;
  client_submission_id: string | null;
  submission_payload: Json | null;
  created_at: string;
  updated_at: string;
};

type FinancialAdjustmentRow = {
  id: string;
  missionary_id: string;
  reporting_period_id: string;
  disbursement_id: string | null;
  expense_id: string | null;
  adjustment_type: "correction" | "reimbursement" | "reversal" | "carry_forward" | "other";
  amount: number;
  currency: string;
  reason: string;
  status: "pending" | "approved" | "rejected";
  requested_by: string;
  approved_by: string | null;
  approved_at: string | null;
  rejected_by: string | null;
  rejected_at: string | null;
  rejection_reason: string | null;
  reversal_of_id: string | null;
  adjustment_date: string | null;
  exchange_rate_to_ghs: number | null;
  exchange_rate_date: string | null;
  exchange_rate_source: string | null;
  client_submission_id: string | null;
  submission_payload: Json | null;
  created_at: string;
};

export type Database = {
  public: {
    Tables: {
      app_users: {
        Row: {
          created_at: string;
          deactivated_at: string | null;
          deactivated_by: string | null;
          display_name: string;
          email: string | null;
          id: string;
          status: "active" | "inactive" | "suspended" | "invited";
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          deactivated_at?: string | null;
          deactivated_by?: string | null;
          display_name: string;
          email?: string | null;
          id: string;
          status?: "active" | "inactive" | "suspended" | "invited";
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          deactivated_at?: string | null;
          deactivated_by?: string | null;
          display_name?: string;
          email?: string | null;
          id?: string;
          status?: "active" | "inactive" | "suspended" | "invited";
          updated_at?: string;
        };
        Relationships: [];
      };
      roles: {
        Row: {
          code: string;
          created_at: string;
          description: string | null;
          id: string;
          is_system_role: boolean;
          name: string;
        };
        Insert: {
          code: string;
          created_at?: string;
          description?: string | null;
          id?: string;
          is_system_role?: boolean;
          name: string;
        };
        Update: {
          code?: string;
          created_at?: string;
          description?: string | null;
          id?: string;
          is_system_role?: boolean;
          name?: string;
        };
        Relationships: [];
      };
      permissions: {
        Row: {
          code: string;
          created_at: string;
          description: string;
          id: string;
          is_sensitive: boolean;
          module: string;
        };
        Insert: {
          code: string;
          created_at?: string;
          description: string;
          id?: string;
          is_sensitive?: boolean;
          module: string;
        };
        Update: {
          code?: string;
          created_at?: string;
          description?: string;
          id?: string;
          is_sensitive?: boolean;
          module?: string;
        };
        Relationships: [];
      };
      user_roles: {
        Row: {
          assigned_at: string;
          assigned_by: string | null;
          expires_at: string | null;
          role_id: string;
          user_id: string;
        };
        Insert: {
          assigned_at?: string;
          assigned_by?: string | null;
          expires_at?: string | null;
          role_id: string;
          user_id: string;
        };
        Update: {
          assigned_at?: string;
          assigned_by?: string | null;
          expires_at?: string | null;
          role_id?: string;
          user_id?: string;
        };
        Relationships: [];
      };
      role_permissions: {
        Row: {
          assigned_at: string;
          assigned_by: string | null;
          permission_id: string;
          role_id: string;
        };
        Insert: {
          assigned_at?: string;
          assigned_by?: string | null;
          permission_id: string;
          role_id: string;
        };
        Update: {
          assigned_at?: string;
          assigned_by?: string | null;
          permission_id?: string;
          role_id?: string;
        };
        Relationships: [];
      };
      user_permissions: {
        Row: {
          assigned_at: string;
          assigned_by: string | null;
          effect: "allow" | "deny";
          expires_at: string | null;
          permission_id: string;
          reason: string;
          user_id: string;
        };
        Insert: {
          assigned_at?: string;
          assigned_by?: string | null;
          effect: "allow" | "deny";
          expires_at?: string | null;
          permission_id: string;
          reason: string;
          user_id: string;
        };
        Update: {
          assigned_at?: string;
          assigned_by?: string | null;
          effect?: "allow" | "deny";
          expires_at?: string | null;
          permission_id?: string;
          reason?: string;
          user_id?: string;
        };
        Relationships: [];
      };
      missionaries: TableDefinition<{
        id: string;
        app_user_id: string | null;
        district_id: string | null;
        display_name: string;
        status: "active" | "inactive";
        created_at: string;
        updated_at: string;
      }>;
      reporting_periods: TableDefinition<{
        id: string;
        period_type: "month" | "quarter" | "half_year" | "year";
        start_date: string;
        end_date: string;
        label: string;
        year: number;
        month_number: number | null;
        period_number: number | null;
        created_at: string;
      }>;
      expense_categories: TableDefinition<{
        id: string;
        code: string;
        name: string;
        is_active: boolean;
        receipt_required: boolean;
        created_at: string;
        updated_at: string;
      }>;
      expenses: TableDefinition<ExpenseRow>;
      expense_lines: TableDefinition<{
        id: string;
        expense_id: string;
        expense_category_id: string;
        line_number: number;
        description: string;
        amount: number;
        created_at: string;
        updated_at: string;
      }>;
      expense_receipts: TableDefinition<{
        id: string;
        expense_id: string;
        file_asset_id: string;
        uploaded_by: string;
        uploaded_at: string;
        supersedes_receipt_id: string | null;
      }>;
      disbursements: TableDefinition<DisbursementRow>;
      disbursement_confirmations: TableDefinition<{
        id: string;
        disbursement_id: string;
        confirmed_by: string;
        decision: "confirm" | "dispute";
        amount_received: number | null;
        received_date: string | null;
        notes: string | null;
        amount_mode: "incremental" | "cumulative" | null;
        client_submission_id: string | null;
        request_payload: Json | null;
        created_at: string;
      }>;
      disbursement_receipts: TableDefinition<{
        id: string;
        disbursement_id: string;
        file_asset_id: string;
        uploaded_by: string;
        uploaded_at: string;
      }>;
      financial_adjustments: TableDefinition<FinancialAdjustmentRow>;
      expense_reviews: TableDefinition<{
        id: string;
        expense_id: string;
        reviewer_id: string;
        decision: "approve" | "reject" | "request_clarification";
        comments: string | null;
        previous_status: string;
        new_status: string;
        created_at: string;
      }>;
      disbursement_resolutions: TableDefinition<{
        id: string;
        disbursement_id: string;
        resolution_type: "resolve_dispute" | "settle_short" | "reconcile_overpayment";
        resolved_by: string;
        notes: string;
        financial_adjustment_id: string | null;
        previous_status: string;
        new_status: string;
        created_at: string;
      }>;
      file_assets: TableDefinition<
        {
          id: string;
          bucket_id: string;
          object_path: string;
          original_filename: string;
          content_type: string;
          size_bytes: number;
          checksum_sha256: string | null;
          upload_status: "pending" | "uploaded" | "failed" | "quarantined";
          uploaded_by: string;
          content_signature_verified_at: string | null;
          created_at: string;
          deleted_at: string | null;
        },
        {
          id?: string;
          bucket_id?: string;
          object_path: string;
          original_filename: string;
          content_type: string;
          size_bytes: number;
          checksum_sha256?: string | null;
          upload_status?: "pending" | "uploaded" | "failed" | "quarantined";
          uploaded_by: string;
          content_signature_verified_at?: string | null;
          created_at?: string;
          deleted_at?: string | null;
        }
      >;
    };
    Views: Record<string, never>;
    Functions: {
      get_financial_period_balance: {
        Args: { p_missionary_id: string; p_reporting_period_id: string };
        Returns: Array<{
          confirmed_received_net_ghs: number;
          approved_expenses_ghs: number;
          carry_forward_ghs: number;
          available_balance_ghs: number;
          reimbursement_due_ghs: number;
        }>;
      };
      create_own_financial_expense: {
        Args: {
          p_reporting_period_id: string;
          p_expense_date: string;
          p_currency: string;
          p_exchange_rate_to_ghs: number;
          p_exchange_rate_date: string | null;
          p_exchange_rate_source: string | null;
          p_description: string;
          p_lines: Json;
          p_client_submission_id: string;
        };
        Returns: string;
      };
      update_own_financial_expense: {
        Args: {
          p_expense_id: string;
          p_reporting_period_id: string;
          p_expense_date: string;
          p_currency: string;
          p_exchange_rate_to_ghs: number;
          p_exchange_rate_date: string | null;
          p_exchange_rate_source: string | null;
          p_description: string;
          p_lines: Json;
          p_client_submission_id: string;
        };
        Returns: string;
      };
      list_financial_missionary_recipients: {
        Args: Record<PropertyKey, never>;
        Returns: Array<{ id: string; display_name: string }>;
      };
      link_financial_receipt: {
        Args: {
          p_record_type: string;
          p_record_id: string;
          p_file_asset_id: string;
          p_supersedes_receipt_id: string | null;
          p_client_submission_id: string;
        };
        Returns: string;
      };
      submit_own_financial_expense: {
        Args: { p_expense_id: string; p_over_funds_note?: string | null };
        Returns: ExpenseRow;
      };
      cancel_own_financial_expense: {
        Args: { p_expense_id: string };
        Returns: ExpenseRow;
      };
      review_financial_expense: {
        Args: { p_expense_id: string; p_decision: string; p_comments?: string | null };
        Returns: ExpenseRow;
      };
      create_financial_disbursement: {
        Args: {
          p_reference: string;
          p_missionary_id: string;
          p_reporting_period_id: string;
          p_amount_sent: number;
          p_currency: string;
          p_sent_date: string;
          p_payment_method: string;
          p_transaction_reference: string | null;
          p_notes: string | null;
          p_exchange_rate_to_ghs: number;
          p_exchange_rate_date: string | null;
          p_exchange_rate_source: string | null;
          p_client_submission_id: string;
        };
        Returns: DisbursementRow;
      };
      record_own_disbursement_confirmation: {
        Args: {
          p_disbursement_id: string;
          p_decision: string;
          p_amount_received: number | null;
          p_received_date: string | null;
          p_amount_mode: string | null;
          p_notes: string | null;
          p_client_submission_id: string;
        };
        Returns: Database["public"]["Tables"]["disbursement_confirmations"]["Row"];
      };
      resolve_financial_disbursement: {
        Args: {
          p_disbursement_id: string;
          p_resolution_type: string;
          p_notes: string;
          p_financial_adjustment_id?: string | null;
        };
        Returns: Database["public"]["Tables"]["disbursement_resolutions"]["Row"];
      };
      create_financial_adjustment: {
        Args: {
          p_reporting_period_id: string;
          p_disbursement_id: string | null;
          p_expense_id: string | null;
          p_adjustment_type: string;
          p_amount: number;
          p_currency: string;
          p_reason: string;
          p_adjustment_date: string;
          p_exchange_rate_to_ghs: number;
          p_exchange_rate_date: string | null;
          p_exchange_rate_source: string | null;
          p_client_submission_id: string;
          p_reversal_of_id?: string | null;
        };
        Returns: FinancialAdjustmentRow;
      };
      approve_financial_adjustment: {
        Args: { p_adjustment_id: string };
        Returns: FinancialAdjustmentRow;
      };
      reject_financial_adjustment: {
        Args: { p_adjustment_id: string; p_reason: string };
        Returns: FinancialAdjustmentRow;
      };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
