export type Database = {
  public: {
    Tables: {
      app_users: {
        Row: {
          created_at: string;
          deactivated_at: string | null;
          deactivated_by: string | null;
          display_name: string;
          id: string;
          status: "active" | "inactive" | "suspended";
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          deactivated_at?: string | null;
          deactivated_by?: string | null;
          display_name: string;
          id: string;
          status?: "active" | "inactive" | "suspended";
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          deactivated_at?: string | null;
          deactivated_by?: string | null;
          display_name?: string;
          id?: string;
          status?: "active" | "inactive" | "suspended";
          updated_at?: string;
        };
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
