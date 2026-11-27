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
    };
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
