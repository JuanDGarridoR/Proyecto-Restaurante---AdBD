--
-- PostgreSQL database dump
--

\restrict b7T5R6fgczsJ9r6moa9DR9Jm7bq3r33YOoOEtuRcFVL4bfRXQw4mM4k9UjZI3IC

-- Dumped from database version 16.14
-- Dumped by pg_dump version 16.14

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: actuaciones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.actuaciones (
    id integer NOT NULL,
    rol_id integer,
    usuario_id integer
);


ALTER TABLE public.actuaciones OWNER TO postgres;

--
-- Name: actuaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.actuaciones_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.actuaciones_id_seq OWNER TO postgres;

--
-- Name: actuaciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.actuaciones_id_seq OWNED BY public.actuaciones.id;


--
-- Name: especialidades; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.especialidades (
    id integer NOT NULL,
    cocinero_id integer,
    plato_id integer
);


ALTER TABLE public.especialidades OWNER TO postgres;

--
-- Name: especialidades_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.especialidades_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.especialidades_id_seq OWNER TO postgres;

--
-- Name: especialidades_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.especialidades_id_seq OWNED BY public.especialidades.id;


--
-- Name: horarios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.horarios (
    id integer NOT NULL,
    mesa_id integer,
    reservacion_id integer,
    inicio timestamp without time zone,
    duracion interval
);


ALTER TABLE public.horarios OWNER TO postgres;

--
-- Name: horarios_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.horarios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.horarios_id_seq OWNER TO postgres;

--
-- Name: horarios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.horarios_id_seq OWNED BY public.horarios.id;


--
-- Name: mesas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.mesas (
    id integer NOT NULL,
    sillas integer
);


ALTER TABLE public.mesas OWNER TO postgres;

--
-- Name: mesas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.mesas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.mesas_id_seq OWNER TO postgres;

--
-- Name: mesas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.mesas_id_seq OWNED BY public.mesas.id;


--
-- Name: ordenes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ordenes (
    id integer NOT NULL,
    plato_id integer,
    pedido_id integer,
    estado integer,
    cantidad integer,
    solicitado timestamp with time zone
);


ALTER TABLE public.ordenes OWNER TO postgres;

--
-- Name: ordenes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ordenes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ordenes_id_seq OWNER TO postgres;

--
-- Name: ordenes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ordenes_id_seq OWNED BY public.ordenes.id;


--
-- Name: pedidos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pedidos (
    id integer NOT NULL,
    cliente_id integer,
    mesero_id integer
);


ALTER TABLE public.pedidos OWNER TO postgres;

--
-- Name: pedidos_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.pedidos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pedidos_id_seq OWNER TO postgres;

--
-- Name: pedidos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.pedidos_id_seq OWNED BY public.pedidos.id;


--
-- Name: platos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.platos (
    id integer NOT NULL,
    tipo_id integer,
    nombre text,
    descripcion text,
    tiempo interval,
    precio numeric
);


ALTER TABLE public.platos OWNER TO postgres;

--
-- Name: platos_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.platos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.platos_id_seq OWNER TO postgres;

--
-- Name: platos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.platos_id_seq OWNED BY public.platos.id;


--
-- Name: preparaciones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.preparaciones (
    id integer NOT NULL,
    cocinero_id integer,
    orden_id integer
);


ALTER TABLE public.preparaciones OWNER TO postgres;

--
-- Name: preparaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.preparaciones_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.preparaciones_id_seq OWNER TO postgres;

--
-- Name: preparaciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.preparaciones_id_seq OWNED BY public.preparaciones.id;


--
-- Name: reservaciones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reservaciones (
    id integer NOT NULL,
    cliente_id integer,
    cantidad integer,
    estado integer
);


ALTER TABLE public.reservaciones OWNER TO postgres;

--
-- Name: reservaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.reservaciones_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reservaciones_id_seq OWNER TO postgres;

--
-- Name: reservaciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.reservaciones_id_seq OWNED BY public.reservaciones.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roles (
    id integer NOT NULL,
    nombre text
);


ALTER TABLE public.roles OWNER TO postgres;

--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roles_id_seq OWNER TO postgres;

--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: tipos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipos (
    id integer NOT NULL,
    nombre text
);


ALTER TABLE public.tipos OWNER TO postgres;

--
-- Name: tipos_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tipos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipos_id_seq OWNER TO postgres;

--
-- Name: tipos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tipos_id_seq OWNED BY public.tipos.id;


--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usuarios (
    id integer NOT NULL,
    nombre text,
    clave bytea,
    fecha_clave timestamp without time zone
);


ALTER TABLE public.usuarios OWNER TO postgres;

--
-- Name: usuarios_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.usuarios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.usuarios_id_seq OWNER TO postgres;

--
-- Name: usuarios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.usuarios_id_seq OWNED BY public.usuarios.id;


--
-- Name: actuaciones id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.actuaciones ALTER COLUMN id SET DEFAULT nextval('public.actuaciones_id_seq'::regclass);


--
-- Name: especialidades id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidades ALTER COLUMN id SET DEFAULT nextval('public.especialidades_id_seq'::regclass);


--
-- Name: horarios id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.horarios ALTER COLUMN id SET DEFAULT nextval('public.horarios_id_seq'::regclass);


--
-- Name: mesas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mesas ALTER COLUMN id SET DEFAULT nextval('public.mesas_id_seq'::regclass);


--
-- Name: ordenes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ordenes ALTER COLUMN id SET DEFAULT nextval('public.ordenes_id_seq'::regclass);


--
-- Name: pedidos id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos ALTER COLUMN id SET DEFAULT nextval('public.pedidos_id_seq'::regclass);


--
-- Name: platos id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.platos ALTER COLUMN id SET DEFAULT nextval('public.platos_id_seq'::regclass);


--
-- Name: preparaciones id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.preparaciones ALTER COLUMN id SET DEFAULT nextval('public.preparaciones_id_seq'::regclass);


--
-- Name: reservaciones id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones ALTER COLUMN id SET DEFAULT nextval('public.reservaciones_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: tipos id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipos ALTER COLUMN id SET DEFAULT nextval('public.tipos_id_seq'::regclass);


--
-- Name: usuarios id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios ALTER COLUMN id SET DEFAULT nextval('public.usuarios_id_seq'::regclass);


--
-- Data for Name: actuaciones; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.actuaciones (id, rol_id, usuario_id) FROM stdin;
1	6	1
2	7	2
3	7	3
4	8	4
5	8	5
6	9	6
7	10	7
8	7	8
9	8	9
\.


--
-- Data for Name: especialidades; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.especialidades (id, cocinero_id, plato_id) FROM stdin;
1	4	3
2	4	6
3	5	4
4	5	5
5	9	8
6	9	9
7	9	10
\.


--
-- Data for Name: horarios; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.horarios (id, mesa_id, reservacion_id, inicio, duracion) FROM stdin;
1	1	1	2026-08-25 12:00:00	02:00:00
2	3	2	2026-08-25 13:00:00	02:00:00
3	6	3	2026-08-26 19:00:00	02:30:00
4	8	4	2026-08-27 19:00:00	02:00:00
5	4	5	2026-08-28 13:00:00	02:00:00
6	2	6	2026-08-25 18:00:00	02:00:00
\.


--
-- Data for Name: mesas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.mesas (id, sillas) FROM stdin;
1	2
2	2
3	4
4	4
5	4
6	6
7	6
8	8
9	8
10	10
\.


--
-- Data for Name: ordenes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ordenes (id, plato_id, pedido_id, estado, cantidad, solicitado) FROM stdin;
1	1	1	1	1	2026-08-20 12:05:00-05
2	3	1	2	2	2026-08-20 12:10:00-05
3	10	1	1	2	2026-08-20 12:11:00-05
4	4	2	2	1	2026-08-20 13:15:00-05
5	7	2	1	1	2026-08-20 13:16:00-05
6	8	2	3	1	2026-08-20 13:45:00-05
7	6	3	2	2	2026-08-21 19:05:00-05
8	12	3	1	2	2026-08-21 19:06:00-05
9	5	4	2	1	2026-08-22 20:00:00-05
10	9	4	1	1	2026-08-22 20:40:00-05
11	3	5	3	1	2026-08-23 14:00:00-05
12	10	5	3	1	2026-08-23 14:01:00-05
\.


--
-- Data for Name: pedidos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pedidos (id, cliente_id, mesero_id) FROM stdin;
1	10	2
2	9	3
3	8	2
4	7	8
5	6	3
\.


--
-- Data for Name: platos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.platos (id, tipo_id, nombre, descripcion, tiempo, precio) FROM stdin;
1	1	Bruschettas de tomate	Pan tostado con tomate fresco, albahaca y aceite de oliva.	00:15:00	14000
2	1	Sopa de tomate	Sopa cremosa de tomate con hierbas aromaticas.	00:20:00	12000
3	2	Pollo a la parrilla	Pechuga de pollo a la parrilla acompanada de vegetales.	00:30:00	28000
4	2	Pasta carbonara	Pasta con salsa cremosa, queso y tocineta.	00:25:00	26000
5	2	Salmon al limon	Filete de salmon con salsa de limon y guarnicion.	00:35:00	42000
6	2	Hamburguesa de la casa	Hamburguesa artesanal con queso, vegetales y papas.	00:25:00	30000
7	5	Ensalada mediterranea	Mezcla de vegetales frescos, aceitunas y queso.	00:15:00	22000
8	3	Tiramisu	Postre italiano de cafe, mascarpone y cacao.	00:10:00	16000
9	3	Cheesecake de frutos rojos	Tarta de queso con salsa de frutos rojos.	00:10:00	17000
10	4	Limonada natural	Limonada preparada con limon fresco.	00:05:00	9000
11	4	Jugo de mango	Jugo natural de mango.	00:05:00	10000
12	4	Cafe americano	Cafe preparado al momento.	00:05:00	7000
\.


--
-- Data for Name: preparaciones; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.preparaciones (id, cocinero_id, orden_id) FROM stdin;
1	4	1
2	4	2
3	4	7
4	4	11
5	5	4
6	5	5
7	5	9
8	9	3
9	9	6
10	9	8
11	9	10
12	9	12
\.


--
-- Data for Name: reservaciones; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reservaciones (id, cliente_id, cantidad, estado) FROM stdin;
1	10	2	1
2	9	4	1
3	8	6	2
4	7	8	1
5	6	4	3
6	3	2	1
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.roles (id, nombre) FROM stdin;
6	Administrador
7	Mesero
8	Cocinero
9	Gerente
10	Recepcionista
\.


--
-- Data for Name: tipos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipos (id, nombre) FROM stdin;
1	Entrada
2	Plato fuerte
3	Postre
4	Bebida
5	Ensalada
\.


--
-- Data for Name: usuarios; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.usuarios (id, nombre, clave, fecha_clave) FROM stdin;
1	Ana Torres	\\x636c6176655f616e615f32303236	2026-08-01 08:00:00
2	Carlos Mendoza	\\x636c6176655f6361726c6f735f32303236	2026-08-02 08:00:00
3	Laura Gomez	\\x636c6176655f6c617572615f32303236	2026-08-03 08:00:00
4	Miguel Rodriguez	\\x636c6176655f6d696775656c5f32303236	2026-08-04 08:00:00
5	Sofia Martinez	\\x636c6176655f736f6669615f32303236	2026-08-05 08:00:00
6	Andres Perez	\\x636c6176655f616e647265735f32303236	2026-08-06 08:00:00
7	Valentina Rojas	\\x636c6176655f76616c656e74696e615f32303236	2026-08-07 08:00:00
8	Diego Castro	\\x636c6176655f646965676f5f32303236	2026-08-08 08:00:00
9	Mariana Lopez	\\x636c6176655f6d617269616e615f32303236	2026-08-09 08:00:00
10	Julian Herrera	\\x636c6176655f6a756c69616e5f32303236	2026-08-10 08:00:00
\.


--
-- Name: actuaciones_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.actuaciones_id_seq', 9, true);


--
-- Name: especialidades_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.especialidades_id_seq', 7, true);


--
-- Name: horarios_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.horarios_id_seq', 6, true);


--
-- Name: mesas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.mesas_id_seq', 10, true);


--
-- Name: ordenes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ordenes_id_seq', 12, true);


--
-- Name: pedidos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.pedidos_id_seq', 5, true);


--
-- Name: platos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.platos_id_seq', 12, true);


--
-- Name: preparaciones_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.preparaciones_id_seq', 12, true);


--
-- Name: reservaciones_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.reservaciones_id_seq', 6, true);


--
-- Name: roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.roles_id_seq', 10, true);


--
-- Name: tipos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipos_id_seq', 5, true);


--
-- Name: usuarios_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.usuarios_id_seq', 10, true);


--
-- Name: actuaciones actuaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.actuaciones
    ADD CONSTRAINT actuaciones_pkey PRIMARY KEY (id);


--
-- Name: especialidades especialidades_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidades
    ADD CONSTRAINT especialidades_pkey PRIMARY KEY (id);


--
-- Name: horarios horarios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.horarios
    ADD CONSTRAINT horarios_pkey PRIMARY KEY (id);


--
-- Name: mesas mesas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mesas
    ADD CONSTRAINT mesas_pkey PRIMARY KEY (id);


--
-- Name: ordenes ordenes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT ordenes_pkey PRIMARY KEY (id);


--
-- Name: pedidos pedidos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_pkey PRIMARY KEY (id);


--
-- Name: platos platos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.platos
    ADD CONSTRAINT platos_pkey PRIMARY KEY (id);


--
-- Name: preparaciones preparaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.preparaciones
    ADD CONSTRAINT preparaciones_pkey PRIMARY KEY (id);


--
-- Name: reservaciones reservaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: tipos tipos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipos
    ADD CONSTRAINT tipos_pkey PRIMARY KEY (id);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: actuaciones actuaciones_rol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.actuaciones
    ADD CONSTRAINT actuaciones_rol_id_fkey FOREIGN KEY (rol_id) REFERENCES public.roles(id);


--
-- Name: actuaciones actuaciones_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.actuaciones
    ADD CONSTRAINT actuaciones_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);


--
-- Name: especialidades especialidades_cocinero_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidades
    ADD CONSTRAINT especialidades_cocinero_id_fkey FOREIGN KEY (cocinero_id) REFERENCES public.usuarios(id);


--
-- Name: especialidades especialidades_plato_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidades
    ADD CONSTRAINT especialidades_plato_id_fkey FOREIGN KEY (plato_id) REFERENCES public.platos(id);


--
-- Name: horarios horarios_mesa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.horarios
    ADD CONSTRAINT horarios_mesa_id_fkey FOREIGN KEY (mesa_id) REFERENCES public.mesas(id);


--
-- Name: horarios horarios_reservacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.horarios
    ADD CONSTRAINT horarios_reservacion_id_fkey FOREIGN KEY (reservacion_id) REFERENCES public.reservaciones(id);


--
-- Name: ordenes ordenes_pedido_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT ordenes_pedido_id_fkey FOREIGN KEY (pedido_id) REFERENCES public.pedidos(id);


--
-- Name: ordenes ordenes_plato_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT ordenes_plato_id_fkey FOREIGN KEY (plato_id) REFERENCES public.platos(id);


--
-- Name: pedidos pedidos_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.usuarios(id);


--
-- Name: pedidos pedidos_mesero_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_mesero_id_fkey FOREIGN KEY (mesero_id) REFERENCES public.usuarios(id);


--
-- Name: platos platos_tipo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.platos
    ADD CONSTRAINT platos_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES public.tipos(id);


--
-- Name: preparaciones preparaciones_cocinero_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.preparaciones
    ADD CONSTRAINT preparaciones_cocinero_id_fkey FOREIGN KEY (cocinero_id) REFERENCES public.usuarios(id);


--
-- Name: preparaciones preparaciones_orden_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.preparaciones
    ADD CONSTRAINT preparaciones_orden_id_fkey FOREIGN KEY (orden_id) REFERENCES public.ordenes(id);


--
-- Name: reservaciones reservaciones_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.usuarios(id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO estudiante;


--
-- Name: TABLE actuaciones; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.actuaciones TO estudiante;


--
-- Name: SEQUENCE actuaciones_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.actuaciones_id_seq TO estudiante;


--
-- Name: TABLE especialidades; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.especialidades TO estudiante;


--
-- Name: SEQUENCE especialidades_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.especialidades_id_seq TO estudiante;


--
-- Name: TABLE horarios; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.horarios TO estudiante;


--
-- Name: SEQUENCE horarios_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.horarios_id_seq TO estudiante;


--
-- Name: TABLE mesas; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.mesas TO estudiante;


--
-- Name: SEQUENCE mesas_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.mesas_id_seq TO estudiante;


--
-- Name: TABLE ordenes; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.ordenes TO estudiante;


--
-- Name: SEQUENCE ordenes_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.ordenes_id_seq TO estudiante;


--
-- Name: TABLE pedidos; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.pedidos TO estudiante;


--
-- Name: SEQUENCE pedidos_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.pedidos_id_seq TO estudiante;


--
-- Name: TABLE platos; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.platos TO estudiante;


--
-- Name: SEQUENCE platos_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.platos_id_seq TO estudiante;


--
-- Name: TABLE preparaciones; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.preparaciones TO estudiante;


--
-- Name: SEQUENCE preparaciones_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.preparaciones_id_seq TO estudiante;


--
-- Name: TABLE reservaciones; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.reservaciones TO estudiante;


--
-- Name: SEQUENCE reservaciones_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.reservaciones_id_seq TO estudiante;


--
-- Name: TABLE roles; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.roles TO estudiante;


--
-- Name: SEQUENCE roles_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.roles_id_seq TO estudiante;


--
-- Name: TABLE tipos; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.tipos TO estudiante;


--
-- Name: SEQUENCE tipos_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.tipos_id_seq TO estudiante;


--
-- Name: TABLE usuarios; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.usuarios TO estudiante;


--
-- Name: SEQUENCE usuarios_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.usuarios_id_seq TO estudiante;


--
-- PostgreSQL database dump complete
--

\unrestrict b7T5R6fgczsJ9r6moa9DR9Jm7bq3r33YOoOEtuRcFVL4bfRXQw4mM4k9UjZI3IC

