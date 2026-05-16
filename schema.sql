-- ============================================================
-- MARINHO INVESTMENT - Schema Supabase Producao
-- Execute no SQL Editor do seu projeto Supabase
-- ============================================================

-- Extensoes
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- 1. Tabelas
-- ============================================================

CREATE TABLE IF NOT EXISTS public.admins (
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.usuarios (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL,
  nome TEXT,
  plano TEXT NOT NULL DEFAULT 'basico' CHECK (plano IN ('basico', 'pro')),
  status TEXT NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'ativo', 'inativo')),
  meta_renda NUMERIC NOT NULL DEFAULT 500 CHECK (meta_renda > 0),
  ip_hash TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.carteira (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  usuario_id UUID REFERENCES public.usuarios(id) ON DELETE CASCADE NOT NULL,
  ticker TEXT NOT NULL,
  quantidade NUMERIC NOT NULL DEFAULT 0 CHECK (quantidade >= 0),
  preco_medio NUMERIC NOT NULL DEFAULT 0 CHECK (preco_medio >= 0),
  cotacao_atual NUMERIC NOT NULL DEFAULT 0 CHECK (cotacao_atual >= 0),
  dividendo_mensal NUMERIC NOT NULL DEFAULT 0 CHECK (dividendo_mensal >= 0),
  setor TEXT DEFAULT 'Outros',
  tipo TEXT NOT NULL DEFAULT 'acao' CHECK (tipo IN ('acao', 'fii', 'renda_fixa')),
  mercado TEXT NOT NULL DEFAULT 'brasil' CHECK (mercado IN ('brasil', 'eua', 'outro')),
  moeda TEXT NOT NULL DEFAULT 'BRL' CHECK (moeda IN ('BRL', 'USD', 'EUR', 'OUTRA')),
  corretora TEXT,
  nota_buffett INTEGER NOT NULL DEFAULT 0 CHECK (nota_buffett >= 0 AND nota_buffett <= 10),
  fallen_angel BOOLEAN NOT NULL DEFAULT FALSE,
  ciclo_entrada TEXT NOT NULL DEFAULT 'recuperacao' CHECK (ciclo_entrada IN ('expansao', 'pico', 'crise', 'recuperacao')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.proventos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  usuario_id UUID REFERENCES public.usuarios(id) ON DELETE CASCADE NOT NULL,
  carteira_id UUID REFERENCES public.carteira(id) ON DELETE SET NULL,
  ticker TEXT NOT NULL,
  tipo TEXT NOT NULL DEFAULT 'dividendo' CHECK (tipo IN ('dividendo', 'jcp', 'rendimento_fii', 'cupom', 'rendimento', 'outro')),
  valor NUMERIC NOT NULL DEFAULT 0 CHECK (valor >= 0),
  moeda TEXT NOT NULL DEFAULT 'BRL' CHECK (moeda IN ('BRL', 'USD', 'EUR', 'OUTRA')),
  data_pagamento DATE NOT NULL DEFAULT CURRENT_DATE,
  competencia TEXT,
  observacao TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_carteira_usuario_id ON public.carteira(usuario_id);
CREATE INDEX IF NOT EXISTS idx_proventos_usuario_id ON public.proventos(usuario_id);
CREATE INDEX IF NOT EXISTS idx_proventos_data_pagamento ON public.proventos(data_pagamento);
CREATE INDEX IF NOT EXISTS idx_usuarios_status ON public.usuarios(status);
CREATE INDEX IF NOT EXISTS idx_usuarios_plano ON public.usuarios(plano);

-- Atualizacao para bases existentes: adiciona cotacao atual sem recriar a tabela.
ALTER TABLE public.carteira
  ADD COLUMN IF NOT EXISTS cotacao_atual NUMERIC NOT NULL DEFAULT 0 CHECK (cotacao_atual >= 0);
ALTER TABLE public.carteira
  ADD COLUMN IF NOT EXISTS mercado TEXT NOT NULL DEFAULT 'brasil' CHECK (mercado IN ('brasil', 'eua', 'outro'));
ALTER TABLE public.carteira
  ADD COLUMN IF NOT EXISTS moeda TEXT NOT NULL DEFAULT 'BRL' CHECK (moeda IN ('BRL', 'USD', 'EUR', 'OUTRA'));
ALTER TABLE public.carteira
  ADD COLUMN IF NOT EXISTS corretora TEXT;

-- ============================================================
-- 2. Helpers seguros
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admins a WHERE a.user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_active_user(target_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.usuarios u
    WHERE u.id = target_user_id
      AND u.status = 'ativo'
  );
$$;

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS touch_usuarios_updated_at ON public.usuarios;
CREATE TRIGGER touch_usuarios_updated_at
  BEFORE UPDATE ON public.usuarios
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS touch_carteira_updated_at ON public.carteira;
CREATE TRIGGER touch_carteira_updated_at
  BEFORE UPDATE ON public.carteira
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS touch_proventos_updated_at ON public.proventos;
CREATE TRIGGER touch_proventos_updated_at
  BEFORE UPDATE ON public.proventos
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ============================================================
-- 3. RLS
-- ============================================================

ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carteira ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.proventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;

-- Recria politicas para permitir rerodar o script sem conflito
DROP POLICY IF EXISTS usuario_select_proprio ON public.usuarios;
DROP POLICY IF EXISTS usuario_update_proprio ON public.usuarios;
DROP POLICY IF EXISTS admin_select_todos ON public.usuarios;
DROP POLICY IF EXISTS admin_update_todos ON public.usuarios;
DROP POLICY IF EXISTS carteira_propria ON public.carteira;
DROP POLICY IF EXISTS admin_carteira_todos ON public.carteira;
DROP POLICY IF EXISTS admin_select_self ON public.admins;
DROP POLICY IF EXISTS usuarios_select_own_or_admin ON public.usuarios;
DROP POLICY IF EXISTS usuarios_update_own_limited ON public.usuarios;
DROP POLICY IF EXISTS usuarios_admin_select ON public.usuarios;
DROP POLICY IF EXISTS carteira_select_active_owner_or_admin ON public.carteira;
DROP POLICY IF EXISTS carteira_insert_active_owner ON public.carteira;
DROP POLICY IF EXISTS carteira_update_active_owner ON public.carteira;
DROP POLICY IF EXISTS carteira_delete_active_owner ON public.carteira;
DROP POLICY IF EXISTS proventos_select_active_owner_or_admin ON public.proventos;
DROP POLICY IF EXISTS proventos_insert_active_owner ON public.proventos;
DROP POLICY IF EXISTS proventos_update_active_owner ON public.proventos;
DROP POLICY IF EXISTS proventos_delete_active_owner ON public.proventos;
DROP POLICY IF EXISTS admins_select_self ON public.admins;

-- Usuarios: o usuario enxerga o proprio perfil; admin enxerga todos.
CREATE POLICY usuarios_select_own_or_admin ON public.usuarios
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id OR public.is_admin());

-- Usuario comum so pode atualizar o proprio registro. Permissoes por coluna abaixo
-- impedem alterar status/plano diretamente pela API publica.
CREATE POLICY usuarios_update_own_limited ON public.usuarios
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Carteira: usuario pendente/inativo nao consegue ler nem escrever, mesmo chamando a API direto.
CREATE POLICY carteira_select_active_owner_or_admin ON public.carteira
  FOR SELECT
  TO authenticated
  USING ((auth.uid() = usuario_id AND public.is_active_user(auth.uid())) OR public.is_admin());

CREATE POLICY carteira_insert_active_owner ON public.carteira
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = usuario_id AND public.is_active_user(auth.uid()));

CREATE POLICY carteira_update_active_owner ON public.carteira
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = usuario_id AND public.is_active_user(auth.uid()))
  WITH CHECK (auth.uid() = usuario_id AND public.is_active_user(auth.uid()));

CREATE POLICY carteira_delete_active_owner ON public.carteira
  FOR DELETE
  TO authenticated
  USING (auth.uid() = usuario_id AND public.is_active_user(auth.uid()));

CREATE POLICY proventos_select_active_owner_or_admin ON public.proventos
  FOR SELECT
  TO authenticated
  USING ((auth.uid() = usuario_id AND public.is_active_user(auth.uid())) OR public.is_admin());

CREATE POLICY proventos_insert_active_owner ON public.proventos
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = usuario_id AND public.is_active_user(auth.uid()));

CREATE POLICY proventos_update_active_owner ON public.proventos
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = usuario_id AND public.is_active_user(auth.uid()))
  WITH CHECK (auth.uid() = usuario_id AND public.is_active_user(auth.uid()));

CREATE POLICY proventos_delete_active_owner ON public.proventos
  FOR DELETE
  TO authenticated
  USING (auth.uid() = usuario_id AND public.is_active_user(auth.uid()));

-- Admins: cada admin consegue confirmar apenas a propria linha.
CREATE POLICY admins_select_self ON public.admins
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- ============================================================
-- 4. Permissoes de API
-- ============================================================

REVOKE ALL ON public.admins FROM anon, authenticated;
REVOKE ALL ON public.usuarios FROM anon, authenticated;
REVOKE ALL ON public.carteira FROM anon, authenticated;
REVOKE ALL ON public.proventos FROM anon, authenticated;

GRANT SELECT ON public.admins TO authenticated;

GRANT SELECT ON public.usuarios TO authenticated;
GRANT UPDATE (nome, meta_renda) ON public.usuarios TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.carteira TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.proventos TO authenticated;

-- ============================================================
-- 5. Funcoes admin
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_update_usuario(
  target_id UUID,
  new_status TEXT,
  new_plano TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Nao autorizado';
  END IF;

  IF new_status NOT IN ('pendente', 'ativo', 'inativo') THEN
    RAISE EXCEPTION 'Status invalido';
  END IF;

  IF new_plano NOT IN ('basico', 'pro') THEN
    RAISE EXCEPTION 'Plano invalido';
  END IF;

  UPDATE public.usuarios
     SET status = new_status,
         plano = new_plano
   WHERE id = target_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_listar_usuarios()
RETURNS TABLE (
  id UUID,
  email TEXT,
  nome TEXT,
  plano TEXT,
  status TEXT,
  meta_renda NUMERIC,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Nao autorizado';
  END IF;

  RETURN QUERY
    SELECT u.id, u.email, u.nome, u.plano, u.status, u.meta_renda, u.created_at
      FROM public.usuarios u
     ORDER BY u.created_at DESC;
END;
$$;


-- Solicita exclusao/anonimizacao da propria conta pelo app.
-- A remocao do usuario em auth.users exige service_role/backend; aqui removemos dados de carteira
-- e desativamos/anonimizamos o perfil publico para cumprir o fluxo LGPD do frontend.
CREATE OR REPLACE FUNCTION public.solicitar_exclusao_conta()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Nao autenticado';
  END IF;

  DELETE FROM public.carteira WHERE usuario_id = auth.uid();

  UPDATE public.usuarios
     SET status = 'inativo',
         nome = 'Conta excluida',
         meta_renda = 500,
         ip_hash = NULL
   WHERE id = auth.uid();
END;
$$;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_active_user(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_usuario(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_listar_usuarios() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.solicitar_exclusao_conta() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_active_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_usuario(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_listar_usuarios() TO authenticated;
GRANT EXECUTE ON FUNCTION public.solicitar_exclusao_conta() TO authenticated;

-- ============================================================
-- 6. Trigger de cadastro via Supabase Auth
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.usuarios (id, email, nome)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'nome', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        nome = COALESCE(public.usuarios.nome, EXCLUDED.nome);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 7. Setup do primeiro admin
-- ============================================================
-- Depois de criar seu usuario pelo index.html:
--
-- INSERT INTO public.admins (user_id) VALUES ('SEU-UUID-AQUI')
-- ON CONFLICT (user_id) DO NOTHING;
--
-- UPDATE public.usuarios
--    SET status = 'ativo', plano = 'pro'
--  WHERE id = 'SEU-UUID-AQUI';
-- ============================================================
