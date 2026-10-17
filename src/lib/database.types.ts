export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: '14.18'
  }
  public: {
    Tables: {
      restaurant_cash_refunds: {
        Row: {
          id: string
          shop_id: string
          session_id: string
          line_id: string
          incident_id: string
          operation_id: string
          amount_xaf: number
          method: string
          reason: string
          confirmed_by: string
          confirmed_at: string
        }
        Insert: {
          id?: string
          shop_id: string
          session_id: string
          line_id: string
          incident_id: string
          operation_id: string
          amount_xaf: number
          method?: string
          reason: string
          confirmed_by: string
          confirmed_at?: string
        }
        Update: {
          id?: string
          shop_id?: string
          session_id?: string
          line_id?: string
          incident_id?: string
          operation_id?: string
          amount_xaf?: number
          method?: string
          reason?: string
          confirmed_by?: string
          confirmed_at?: string
        }
        Relationships: []
      }
      restaurant_served_incidents: {
        Row: {
          id: string
          shop_id: string
          session_id: string
          line_id: string
          reported_by: string
          operation_id: string
          description: string
          state: string
          owner_note: string | null
          reviewed_by: string | null
          created_at: string
          reviewed_at: string | null
        }
        Insert: {
          id?: string
          shop_id: string
          session_id: string
          line_id: string
          reported_by: string
          operation_id: string
          description: string
          state?: string
          owner_note?: string | null
          reviewed_by?: string | null
          created_at?: string
          reviewed_at?: string | null
        }
        Update: {
          id?: string
          shop_id?: string
          session_id?: string
          line_id?: string
          reported_by?: string
          operation_id?: string
          description?: string
          state?: string
          owner_note?: string | null
          reviewed_by?: string | null
          created_at?: string
          reviewed_at?: string | null
        }
        Relationships: []
      }
      restaurant_staff_members: {
        Row: {
          id: string
          shop_id: string
          user_id: string
          display_name: string
          staff_role: string
          active: boolean
          created_by: string
          created_at: string
          disabled_at: string | null
        }
        Insert: {
          id?: string
          shop_id: string
          user_id: string
          display_name: string
          staff_role: string
          active?: boolean
          created_by: string
          created_at?: string
          disabled_at?: string | null
        }
        Update: {
          id?: string
          shop_id?: string
          user_id?: string
          display_name?: string
          staff_role?: string
          active?: boolean
          created_by?: string
          created_at?: string
          disabled_at?: string | null
        }
        Relationships: []
      }
      restaurant_staff_events: {
        Row: {
          id: number
          shop_id: string
          actor_user_id: string
          session_id: string | null
          line_id: string | null
          event_type: string
          details: Json
          occurred_at: string
        }
        Insert: {
          id?: number
          shop_id: string
          actor_user_id: string
          session_id?: string | null
          line_id?: string | null
          event_type: string
          details?: Json
          occurred_at?: string
        }
        Update: {
          id?: number
          shop_id?: string
          actor_user_id?: string
          session_id?: string | null
          line_id?: string | null
          event_type?: string
          details?: Json
          occurred_at?: string
        }
        Relationships: []
      }
      restaurant_drink_adjustments: {
        Row: {
          id: string
          shop_id: string
          menu_item_id: string
          quantity_delta: number
          stock_after: number
          reason: string
          created_by: string
          created_at: string
        }
        Insert: {
          id?: string
          shop_id: string
          menu_item_id: string
          quantity_delta: number
          stock_after: number
          reason: string
          created_by: string
          created_at?: string
        }
        Update: {
          id?: string
          shop_id?: string
          menu_item_id?: string
          quantity_delta?: number
          stock_after?: number
          reason?: string
          created_by?: string
          created_at?: string
        }
        Relationships: []
      }
      restaurant_table_sessions: {
        Row: {
          id: string
          shop_id: string
          table_id: string
          status: string
          guest_count: number
          order_number: number | null
          order_reference: string | null
          created_at: string
          submitted_at: string | null
          closed_at: string | null
        }
        Insert: {
          id?: string
          shop_id: string
          table_id: string
          status?: string
          guest_count?: number
          order_number?: number | null
          order_reference?: string | null
          created_at?: string
          submitted_at?: string | null
          closed_at?: string | null
        }
        Update: {
          id?: string
          shop_id?: string
          table_id?: string
          status?: string
          guest_count?: number
          order_number?: number | null
          order_reference?: string | null
          created_at?: string
          submitted_at?: string | null
          closed_at?: string | null
        }
        Relationships: []
      }
      restaurant_participants: {
        Row: {
          id: string
          shop_id: string
          session_id: string
          participant_token: string
          ready: boolean
          is_leader: boolean
          created_at: string
        }
        Insert: {
          id?: string
          shop_id: string
          session_id: string
          participant_token?: string
          ready?: boolean
          is_leader?: boolean
          created_at?: string
        }
        Update: {
          id?: string
          shop_id?: string
          session_id?: string
          participant_token?: string
          ready?: boolean
          is_leader?: boolean
          created_at?: string
        }
        Relationships: []
      }
      restaurant_session_lines: {
        Row: {
          id: string
          shop_id: string
          session_id: string
          participant_id: string | null
          menu_item_id: string
          quantity: number
          unit_price_xaf: number
          status: string
          created_by: string | null
          created_at: string
          served_at: string | null
        }
        Insert: {
          id?: string
          shop_id: string
          session_id: string
          participant_id?: string | null
          menu_item_id: string
          quantity: number
          unit_price_xaf: number
          status?: string
          created_by?: string | null
          created_at?: string
          served_at?: string | null
        }
        Update: {
          id?: string
          shop_id?: string
          session_id?: string
          participant_id?: string | null
          menu_item_id?: string
          quantity?: number
          unit_price_xaf?: number
          status?: string
          created_by?: string | null
          created_at?: string
          served_at?: string | null
        }
        Relationships: []
      }
      restaurant_order_counters: {
        Row: {
          shop_id: string
          next_number: number
        }
        Insert: {
          shop_id: string
          next_number: number
        }
        Update: {
          shop_id?: string
          next_number?: number
        }
        Relationships: []
      }
      restaurant_cash_payments: {
        Row: {
          id: string
          shop_id: string
          session_id: string
          operation_id: string
          amount_xaf: number
          method: string
          confirmed_by: string
          confirmed_at: string
        }
        Insert: {
          id?: string
          shop_id: string
          session_id: string
          operation_id: string
          amount_xaf: number
          method: string
          confirmed_by: string
          confirmed_at?: string
        }
        Update: {
          id?: string
          shop_id?: string
          session_id?: string
          operation_id?: string
          amount_xaf?: number
          method?: string
          confirmed_by?: string
          confirmed_at?: string
        }
        Relationships: []
      }
      restaurant_drink_movements: {
        Row: {
          id: string
          shop_id: string
          session_id: string
          line_id: string
          menu_item_id: string
          quantity_delta: number
          stock_after: number
          created_by: string
          created_at: string
        }
        Insert: {
          id?: string
          shop_id: string
          session_id: string
          line_id: string
          menu_item_id: string
          quantity_delta: number
          stock_after: number
          created_by: string
          created_at?: string
        }
        Update: {
          id?: string
          shop_id?: string
          session_id?: string
          line_id?: string
          menu_item_id?: string
          quantity_delta?: number
          stock_after?: number
          created_by?: string
          created_at?: string
        }
        Relationships: []
      }
      restaurant_tables: {
        Row: {
          id: string
          shop_id: string
          label: string
          zone: string
          capacity: number
          pos_x: number
          pos_y: number
          qr_token: string
          active: boolean
          created_at: string
        }
        Insert: {
          id?: string
          shop_id: string
          label: string
          zone?: string
          capacity?: number
          pos_x?: number
          pos_y?: number
          qr_token?: string
          active?: boolean
          created_at?: string
        }
        Update: {
          id?: string
          shop_id?: string
          label?: string
          zone?: string
          capacity?: number
          pos_x?: number
          pos_y?: number
          qr_token?: string
          active?: boolean
          created_at?: string
        }
        Relationships: []
      }
      restaurant_menu_items: {
        Row: {
          id: string
          shop_id: string
          name: string
          category: string
          kind: string
          price_xaf: number
          available: boolean
          drink_stock: number | null
          created_at: string
        }
        Insert: {
          id?: string
          shop_id: string
          name: string
          category: string
          kind: string
          price_xaf: number
          available?: boolean
          drink_stock?: number | null
          created_at?: string
        }
        Update: {
          id?: string
          shop_id?: string
          name?: string
          category?: string
          kind?: string
          price_xaf?: number
          available?: boolean
          drink_stock?: number | null
          created_at?: string
        }
        Relationships: []
      }
      salon_services: {
        Row: {
          id: string
          shop_id: string
          name: string
          price_xaf: number
          duration_minutes: number
          active: boolean
          created_at: string
        }
        Insert: {
          id?: string
          shop_id: string
          name: string
          price_xaf: number
          duration_minutes: number
          active?: boolean
          created_at?: string
        }
        Update: {
          id?: string
          shop_id?: string
          name?: string
          price_xaf?: number
          duration_minutes?: number
          active?: boolean
          created_at?: string
        }
        Relationships: []
      }
      salon_booking_links: {
        Row: {
          shop_id: string
          public_token: string
          enabled: boolean
          created_at: string
        }
        Insert: {
          shop_id: string
          public_token?: string
          enabled?: boolean
          created_at?: string
        }
        Update: {
          shop_id?: string
          public_token?: string
          enabled?: boolean
          created_at?: string
        }
        Relationships: []
      }
      salon_booking_requests: {
        Row: {
          duration_minutes: number | null
          id: string
          shop_id: string
          service_id: string | null
          first_name: string
          last_name: string
          phone: string
          requested_at: string
          status: string
          created_at: string
        }
        Insert: {
          duration_minutes?: number | null
          id?: string
          shop_id: string
          service_id?: string | null
          first_name: string
          last_name: string
          phone: string
          requested_at: string
          status?: string
          created_at?: string
        }
        Update: {
          duration_minutes?: number | null
          id?: string
          shop_id?: string
          service_id?: string | null
          first_name?: string
          last_name?: string
          phone?: string
          requested_at?: string
          status?: string
          created_at?: string
        }
        Relationships: []
      }
      employees: {
        Row: {
          id: string
          shop_id: string
          full_name: string
          job_title: string
          compensation_mode: string
          monthly_salary: number
          commission_percent: number
          hired_on: string | null
          active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          shop_id: string
          full_name: string
          job_title: string
          compensation_mode?: string
          monthly_salary?: number
          commission_percent?: number
          hired_on?: string | null
          active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          shop_id?: string
          full_name?: string
          job_title?: string
          compensation_mode?: string
          monthly_salary?: number
          commission_percent?: number
          hired_on?: string | null
          active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'employees_shop_id_fkey'
            columns: ['shop_id']
            isOneToOne: false
            referencedRelation: 'shops'
            referencedColumns: ['id']
          },
        ]
      }
      arrivals: {
        Row: {
          code: string
          created_at: string
          customs_cost: number
          global_cost: number
          id: string
          is_test: boolean
          kind: string
          merchandise_cost: number
          order_date: string | null
          origin_country: string | null
          received_date: string | null
          shop_id: string
          status: string
          supplier_name: string | null
          transport_cost: number
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          customs_cost?: number
          global_cost?: number
          id?: string
          is_test?: boolean
          kind: string
          merchandise_cost?: number
          order_date?: string | null
          origin_country?: string | null
          received_date?: string | null
          shop_id: string
          status?: string
          supplier_name?: string | null
          transport_cost?: number
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          customs_cost?: number
          global_cost?: number
          id?: string
          is_test?: boolean
          kind?: string
          merchandise_cost?: number
          order_date?: string | null
          origin_country?: string | null
          received_date?: string | null
          shop_id?: string
          status?: string
          supplier_name?: string | null
          transport_cost?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'arrivals_shop_id_fkey'
            columns: ['shop_id']
            isOneToOne: false
            referencedRelation: 'shops'
            referencedColumns: ['id']
          },
        ]
      }
      products: {
        Row: {
          arrival_id: string | null
          brand: string | null
          category: string | null
          created_at: string
          id: string
          image_path: string | null
          initial_sale_price: number
          is_test: boolean
          is_unique_piece: boolean
          name: string
          quantity_on_hand: number
          shop_id: string
          size: string | null
          status: string
          updated_at: string
        }
        Insert: {
          arrival_id?: string | null
          brand?: string | null
          category?: string | null
          created_at?: string
          id?: string
          image_path?: string | null
          initial_sale_price?: number
          is_test?: boolean
          is_unique_piece?: boolean
          name: string
          quantity_on_hand?: number
          shop_id: string
          size?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          arrival_id?: string | null
          brand?: string | null
          category?: string | null
          created_at?: string
          id?: string
          image_path?: string | null
          initial_sale_price?: number
          is_test?: boolean
          is_unique_piece?: boolean
          name?: string
          quantity_on_hand?: number
          shop_id?: string
          size?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'products_arrival_id_fkey'
            columns: ['arrival_id']
            isOneToOne: false
            referencedRelation: 'arrivals'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'products_shop_id_fkey'
            columns: ['shop_id']
            isOneToOne: false
            referencedRelation: 'shops'
            referencedColumns: ['id']
          },
        ]
      }
      sale_items: {
        Row: {
          id: string
          initial_unit_price: number
          product_id: string
          quantity: number
          sale_id: string
          sold_unit_price: number
        }
        Insert: {
          id?: string
          initial_unit_price: number
          product_id: string
          quantity?: number
          sale_id: string
          sold_unit_price: number
        }
        Update: {
          id?: string
          initial_unit_price?: number
          product_id?: string
          quantity?: number
          sale_id?: string
          sold_unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: 'sale_items_product_id_fkey'
            columns: ['product_id']
            isOneToOne: false
            referencedRelation: 'products'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'sale_items_sale_id_fkey'
            columns: ['sale_id']
            isOneToOne: false
            referencedRelation: 'sales'
            referencedColumns: ['id']
          },
        ]
      }
      sales: {
        Row: {
          cashier_profile_id: string | null
          client_operation_id: string | null
          id: string
          is_test: boolean
          payment_method: string
          shop_id: string
          seller_id: string | null
          sold_at: string
          total_amount: number
        }
        Insert: {
          cashier_profile_id?: string | null
          client_operation_id?: string | null
          id?: string
          is_test?: boolean
          payment_method: string
          shop_id: string
          seller_id?: string | null
          sold_at?: string
          total_amount?: number
        }
        Update: {
          cashier_profile_id?: string | null
          client_operation_id?: string | null
          id?: string
          is_test?: boolean
          payment_method?: string
          shop_id?: string
          seller_id?: string | null
          sold_at?: string
          total_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: 'sales_shop_id_fkey'
            columns: ['shop_id']
            isOneToOne: false
            referencedRelation: 'shops'
            referencedColumns: ['id']
          },
        ]
      }
      shop_expenses: {
        Row: {
          amount: number
          category: string
          created_at: string
          expense_date: string
          id: string
          is_test: boolean
          label: string
          recurring: boolean
          shop_id: string
        }
        Insert: {
          amount: number
          category: string
          created_at?: string
          expense_date?: string
          id?: string
          is_test?: boolean
          label: string
          recurring?: boolean
          shop_id: string
        }
        Update: {
          amount?: number
          category?: string
          created_at?: string
          expense_date?: string
          id?: string
          is_test?: boolean
          label?: string
          recurring?: boolean
          shop_id?: string
        }
        Relationships: [
          {
            foreignKeyName: 'shop_expenses_shop_id_fkey'
            columns: ['shop_id']
            isOneToOne: false
            referencedRelation: 'shops'
            referencedColumns: ['id']
          },
        ]
      }
      shops: {
        Row: {
          business_kind: string
          city: string | null
          country: string | null
          latitude: number | null
          longitude: number | null
          location_accuracy_m: number | null
          created_at: string
          currency: string
          id: string
          name: string
          neighborhood: string | null
          owner_id: string
        }
        Insert: {
          business_kind?: string
          city?: string | null
          country?: string | null
          latitude?: number | null
          longitude?: number | null
          location_accuracy_m?: number | null
          created_at?: string
          currency?: string
          id?: string
          name: string
          neighborhood?: string | null
          owner_id: string
        }
        Update: {
          business_kind?: string
          city?: string | null
          country?: string | null
          latitude?: number | null
          longitude?: number | null
          location_accuracy_m?: number | null
          created_at?: string
          currency?: string
          id?: string
          name?: string
          neighborhood?: string | null
          owner_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      restaurant_cash_refund_quote: {
        Args: { p_shop: string; p_incident: string }
        Returns: Json
      }
      restaurant_confirm_cash_refund: {
        Args: {
          p_shop: string
          p_incident: string
          p_amount: number
          p_reason: string
          p_operation_id: string
          p_cash_handed_over: boolean
        }
        Returns: Json
      }
      restaurant_report_served_issue: {
        Args: { p_shop: string; p_line: string; p_description: string; p_operation_id: string }
        Returns: Json
      }
      restaurant_review_served_issue: {
        Args: { p_shop: string; p_ticket: string; p_decision: string; p_note: string }
        Returns: boolean
      }
      restaurant_cancel_order_line: {
        Args: { p_shop: string; p_line: string; p_reason: string }
        Returns: Json
      }
      restaurant_cancel_empty_table: {
        Args: { p_shop: string; p_session: string; p_reason: string }
        Returns: boolean
      }
      restaurant_issue_group_code: {
        Args: { p_shop: string; p_session: string }
        Returns: string
      }
      restaurant_staff_my_spaces: {
        Args: Record<PropertyKey, never>
        Returns: { shop_id: string; shop_name: string; staff_role: string; display_name: string }[]
      }
      restaurant_staff_create_invite: {
        Args: { p_shop: string; p_name: string; p_role: string }
        Returns: Json
      }
      restaurant_staff_join: {
        Args: { p_code: string }
        Returns: Json
      }
      restaurant_staff_pending_invites: {
        Args: { p_shop: string }
        Returns: { id: string; display_name: string; staff_role: string; expires_at: string }[]
      }
      restaurant_staff_revoke_invite: {
        Args: { p_shop: string; p_invite: string }
        Returns: boolean
      }
      restaurant_staff_disable: {
        Args: { p_shop: string; p_member: string }
        Returns: boolean
      }
      restaurant_staff_room: {
        Args: { p_shop: string }
        Returns: Json
      }
      salon_change_booking_status: {
        Args: { p_shop: string; p_booking: string; p_status: string }
        Returns: string
      }
      restaurant_adjust_drink_stock: {
        Args: { p_shop: string; p_item: string; p_delta: number; p_reason: string }
        Returns: number
      }
      restaurant_open_table: {
        Args: { p_shop: string; p_table: string; p_guest_count: number }
        Returns: string
      }
      restaurant_add_participant: {
        Args: { p_shop: string; p_session: string }
        Returns: string
      }
      restaurant_choose_item: {
        Args: {
          p_shop: string
          p_session: string
          p_participant: string
          p_item: string
          p_quantity: number
        }
        Returns: string | null
      }
      restaurant_mark_ready: {
        Args: { p_shop: string; p_session: string; p_participant: string }
        Returns: boolean
      }
      restaurant_submit_group: {
        Args: { p_shop: string; p_session: string; p_leader: string }
        Returns: string
      }
      restaurant_staff_add_item: {
        Args: { p_shop: string; p_session: string; p_item: string; p_quantity: number }
        Returns: string
      }
      restaurant_mark_served: {
        Args: { p_shop: string; p_line: string }
        Returns: void
      }
      restaurant_capture_cash: {
        Args: { p_shop: string; p_session: string; p_amount: number; p_operation_id: string }
        Returns: boolean
      }
      create_my_shop: {
        Args: {
          p_city?: string
          p_country?: string
          p_currency?: string
          p_name: string
        }
        Returns: {
          business_kind: string
          city: string | null
          country: string | null
          latitude: number | null
          longitude: number | null
          location_accuracy_m: number | null
          created_at: string
          currency: string
          id: string
          name: string
          neighborhood: string | null
          owner_id: string
        }
        SetofOptions: {
          from: '*'
          to: 'shops'
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_my_shop_with_neighborhood: {
        Args: {
          p_city: string
          p_country: string
          p_currency?: string
          p_name: string
          p_neighborhood: string
        }
        Returns: {
          business_kind: string
          city: string | null
          country: string | null
          latitude: number | null
          longitude: number | null
          location_accuracy_m: number | null
          created_at: string
          currency: string
          id: string
          name: string
          neighborhood: string | null
          owner_id: string
        }
        SetofOptions: {
          from: '*'
          to: 'shops'
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_my_shop_with_location: {
        Args: {
          p_name: string
          p_city: string
          p_country: string
          p_neighborhood: string
          p_currency?: string
          p_latitude?: number
          p_longitude?: number
          p_location_accuracy_m?: number
        }
        Returns: {
          business_kind: string
          city: string | null
          country: string | null
          created_at: string
          currency: string
          id: string
          latitude: number | null
          longitude: number | null
          location_accuracy_m: number | null
          name: string
          neighborhood: string | null
          owner_id: string
        }
        SetofOptions: {
          from: '*'
          to: 'shops'
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_my_business_with_location: {
        Args: {
          p_name: string
          p_city: string
          p_country: string
          p_neighborhood: string
          p_business_kind: string
          p_currency?: string
          p_latitude?: number
          p_longitude?: number
          p_location_accuracy_m?: number
        }
        Returns: {
          business_kind: string
          city: string | null
          country: string | null
          created_at: string
          currency: string
          id: string
          latitude: number | null
          longitude: number | null
          location_accuracy_m: number | null
          name: string
          neighborhood: string | null
          owner_id: string
        }
        SetofOptions: {
          from: '*'
          to: 'shops'
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_sale: {
        Args: {
          p_client_operation_id: string
          p_payment_method: string
          p_product_id: string
          p_quantity: number
          p_shop_id: string
          p_sold_unit_price: number
          p_till_session?: string
        }
        Returns: string
      }
      record_cart_sale: {
        Args: {
          p_client_operation_id: string
          p_items: Json
          p_payment_method: string
          p_shop_id: string
          p_till_session?: string
        }
        Returns: string
      }
      create_member_invite: {
        Args: {
          p_shop_id: string
          p_display_name: string
          p_can_view_shop_sales?: boolean
          p_max_discount_pct?: number
        }
        Returns: Json
      }
      list_member_invites: {
        Args: { p_shop_id: string }
        Returns: {
          id: string
          display_name: string
          can_view_shop_sales: boolean
          max_discount_pct: number
          created_at: string
          expires_at: string
        }[]
      }
      revoke_member_invite: { Args: { p_invite_id: string }; Returns: boolean }
      redeem_member_invite: { Args: { p_code: string }; Returns: Json }
      list_shop_members: {
        Args: { p_shop_id: string }
        Returns: {
          id: string
          user_id: string
          display_name: string
          role: string
          active: boolean
          can_view_shop_sales: boolean
          max_discount_pct: number
          created_at: string
          updated_at: string
          deactivated_at: string | null
          pin_set: boolean
          pin_must_change: boolean
          pin_locked_until: string | null
        }[]
      }
      set_member_active: { Args: { p_member_id: string; p_active: boolean }; Returns: Json }
      set_member_permissions: {
        Args: { p_member_id: string; p_can_view_shop_sales: boolean; p_max_discount_pct: number }
        Returns: Json
      }
      owner_reset_member_pin: { Args: { p_member_id: string }; Returns: Json }
      my_member_shops: {
        Args: Record<PropertyKey, never>
        Returns: {
          member_id: string
          shop_id: string
          shop_name: string
          shop_city: string | null
          shop_country: string | null
          shop_currency: string
          display_name: string
          role: string
          can_view_shop_sales: boolean
          max_discount_pct: number
          pin_set: boolean
          pin_must_change: boolean
        }[]
      }
      set_my_pin: {
        Args: { p_shop_id: string; p_new_pin: string; p_current_pin?: string }
        Returns: Json
      }
      verify_my_pin: { Args: { p_shop_id: string; p_pin: string }; Returns: Json }
      open_till_session: {
        Args: { p_shop_id: string; p_member_id: string; p_pin: string }
        Returns: Json
      }
      close_till_session: { Args: { p_shop_id: string; p_token: string }; Returns: boolean }
      owner_pin_status: { Args: { p_shop_id: string }; Returns: Json }
      set_owner_pin: {
        Args: { p_shop_id: string; p_new_pin: string; p_current_pin?: string }
        Returns: Json
      }
      reset_owner_pin: { Args: { p_shop_id: string }; Returns: boolean }
      verify_owner_pin: { Args: { p_shop_id: string; p_pin: string }; Returns: Json }
      leave_counter_mode: {
        Args: { p_shop_id: string; p_pin: string; p_token?: string }
        Returns: Json
      }
      unlock_till_session: {
        Args: { p_shop_id: string; p_token: string; p_pin: string }
        Returns: Json
      }
      list_shared_cashiers: { Args: { p_shop_id: string }; Returns: Json }
      create_shared_cashier: {
        Args: {
          p_shop_id: string
          p_display_name: string
          p_pin: string
          p_max_discount_pct?: number
          p_can_view_shop_sales?: boolean
        }
        Returns: Json
      }
      set_shared_cashier_active: {
        Args: { p_cashier_id: string; p_active: boolean }
        Returns: boolean
      }
      open_shared_cashier_till: {
        Args: { p_shop_id: string; p_cashier_id: string; p_pin: string }
        Returns: Json
      }
      unlock_shared_cashier_till: {
        Args: { p_shop_id: string; p_token: string; p_pin: string }
        Returns: Json
      }
      close_shared_cashier_till: {
        Args: { p_shop_id: string; p_token: string }
        Returns: boolean
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, 'public'>]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    ? (DefaultSchema['Tables'] & DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema['Enums'] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
    ? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema['CompositeTypes'] | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
    ? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
