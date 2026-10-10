export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: '14.18'
  }
  public: {
    Tables: {
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
          client_operation_id: string | null
          id: string
          is_test: boolean
          payment_method: string
          shop_id: string
          sold_at: string
          total_amount: number
        }
        Insert: {
          client_operation_id?: string | null
          id?: string
          is_test?: boolean
          payment_method: string
          shop_id: string
          sold_at?: string
          total_amount?: number
        }
        Update: {
          client_operation_id?: string | null
          id?: string
          is_test?: boolean
          payment_method?: string
          shop_id?: string
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
          city: string | null
          country: string | null
          created_at: string
          currency: string
          id: string
          name: string
          owner_id: string
        }
        Insert: {
          city?: string | null
          country?: string | null
          created_at?: string
          currency?: string
          id?: string
          name: string
          owner_id: string
        }
        Update: {
          city?: string | null
          country?: string | null
          created_at?: string
          currency?: string
          id?: string
          name?: string
          owner_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      arrival_cost_allocation: {
        Args: { p_include_test?: boolean; p_shop_id: string }
        Returns: {
          arrival_id: string
          arrival_kind: string
          initial_sale_price: number
          method: string
          product_id: string
          registered_units: number
          remaining_cost: number
          remaining_units: number
          sold_cost: number
          sold_units: number
          unit_cost: number
        }[]
      }
      arrival_profitability: {
        Args: { p_include_test?: boolean; p_shop_id: string }
        Returns: {
          arrival_id: string
          code: string
          cost: number
          is_test: boolean
          kind: string
          order_date: string
          origin_country: string
          product_count: number
          profit: number
          received_date: string
          recovery_percent: number
          remaining_to_recover: number
          remaining_units: number
          revenue: number
          sold_units: number
          status: string
          supplier_name: string
        }[]
      }
      create_my_shop: {
        Args: {
          p_city?: string
          p_country?: string
          p_currency?: string
          p_name: string
        }
        Returns: {
          city: string | null
          country: string | null
          created_at: string
          currency: string
          id: string
          name: string
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
        }
        Returns: string
      }
      shop_dashboard: {
        Args: {
          p_at?: string
          p_include_test?: boolean
          p_shop_id: string
          p_tz?: string
        }
        Returns: Json
      }
      shop_estimated_profit: {
        Args: {
          p_from?: string
          p_include_test?: boolean
          p_shop_id: string
          p_to?: string
          p_tz?: string
        }
        Returns: Json
      }
      shop_monthly_sales: {
        Args: {
          p_at?: string
          p_include_test?: boolean
          p_months?: number
          p_shop_id: string
          p_tz?: string
        }
        Returns: Json
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
