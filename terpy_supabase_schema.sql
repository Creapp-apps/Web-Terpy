-- ============================================
-- TERPY — Supabase Schema completo
-- Pegar en SQL Editor de Supabase y ejecutar
-- ============================================

create extension if not exists "uuid-ossp";

-- ── PRODUCTS ──────────────────────────────
create table if not exists products (
  id            uuid primary key default uuid_generate_v4(),
  name          text not null,
  slug          text unique not null,
  description   text,
  terpeno       text,
  efecto        text,
  price         numeric(10,2) not null,
  stock         integer not null default 0,
  image_url     text,
  color_accent  text,
  active        boolean default true,
  created_at    timestamptz default now()
);

insert into products (name, slug, description, terpeno, efecto, price, stock, image_url, color_accent) values
  ('Mango Kush',     'mango-kush',     'Yerba mate ultra-premium con terpenos de Mirceno. Alerta relajada y relajación profunda sin perder el foco.', 'Mirceno', 'Alerta relajada · Relajante profundo', 4500, 200, 'hero-mango.png',  '#a07ed4'),
  ('Lemon Kush',     'lemon-kush',     'Yerba mate ultra-premium con terpenos de Limoneno. Boost cognitivo y concentración máxima ceba a ceba.',       'Limoneno', 'Boost cognitivo · Concentración',     4500, 200, 'hero-lemon.png',  '#c8922a'),
  ('Orange Cookies', 'orange-cookies', 'Yerba mate ultra-premium con Limoneno y Terpineol. Chispa creativa y relax social en cada mate.',              'Limoneno + Terpineol', 'Chispa creativa · Relax social', 4500, 200, 'hero-orange.png', '#e07830');

-- ── PROFILES ──────────────────────────────
create table if not exists profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  email       text,
  phone       text,
  address     jsonb,
  created_at  timestamptz default now()
);

create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into profiles (id, email) values (new.id, new.email);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ── ORDERS ────────────────────────────────
create table if not exists orders (
  id               uuid primary key default uuid_generate_v4(),
  user_id          uuid references profiles(id) on delete set null,
  email            text not null,
  status           text not null default 'pending'
                     check (status in ('pending','paid','shipped','delivered','cancelled')),
  total            numeric(10,2) not null,
  shipping_address jsonb,
  payment_ref      text,
  payment_method   text default 'mercadopago',
  notes            text,
  created_at       timestamptz default now(),
  updated_at       timestamptz default now()
);

-- ── ORDER ITEMS ───────────────────────────
create table if not exists order_items (
  id          uuid primary key default uuid_generate_v4(),
  order_id    uuid references orders(id) on delete cascade,
  product_id  uuid references products(id) on delete set null,
  quantity    integer not null default 1,
  unit_price  numeric(10,2) not null
);

-- ── CART ITEMS ────────────────────────────
create table if not exists cart_items (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references profiles(id) on delete cascade,
  session_id  text,
  product_id  uuid references products(id) on delete cascade,
  quantity    integer not null default 1,
  created_at  timestamptz default now(),
  unique(user_id, product_id),
  unique(session_id, product_id)
);

-- ── NEWSLETTER ────────────────────────────
create table if not exists newsletter (
  id            uuid primary key default uuid_generate_v4(),
  email         text unique not null,
  name          text,
  source        text default 'website',
  subscribed_at timestamptz default now()
);

-- ── ROW LEVEL SECURITY ────────────────────
alter table products     enable row level security;
alter table profiles     enable row level security;
alter table orders       enable row level security;
alter table order_items  enable row level security;
alter table cart_items   enable row level security;
alter table newsletter   enable row level security;

create policy "products_public_read"  on products    for select using (active = true);
create policy "profiles_owner"        on profiles    for all    using (auth.uid() = id);
create policy "orders_owner_read"     on orders      for select using (auth.uid() = user_id);
create policy "orders_insert"         on orders      for insert with check (true);
create policy "order_items_read"      on order_items for select using (
  exists (select 1 from orders where orders.id = order_id and orders.user_id = auth.uid())
);
create policy "order_items_insert"    on order_items for insert with check (true);
create policy "cart_owner"            on cart_items  for all    using (auth.uid() = user_id or session_id is not null);
create policy "newsletter_insert"     on newsletter  for insert with check (true);

-- ── STOCK: descontar al pagar ──────────────
create or replace function decrease_stock_on_order()
returns trigger language plpgsql as $$
begin
  if new.status = 'paid' and old.status = 'pending' then
    update products p
    set stock = stock - oi.quantity
    from order_items oi
    where oi.order_id = new.id and oi.product_id = p.id;
  end if;
  return new;
end;
$$;

create trigger trg_decrease_stock
  after update on orders
  for each row execute function decrease_stock_on_order();

-- ── UPDATED_AT automático ─────────────────
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create trigger trg_orders_updated_at
  before update on orders
  for each row execute function set_updated_at();
