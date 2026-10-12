import './style.css';

// Un solo front (Vite) para las 5 APIs. Todas las llamadas van a "/api/<servicio>/..."
// -> en produccion NGINX reenvia cada prefijo al contenedor que corresponde (ver nginx.conf);
// en desarrollo lo hace el proxy de Vite (ver vite.config.js).
// "name" es el campo que viaja a la API; "label" es solo lo que se muestra en pantalla.
// Validacion del lado del navegador (las APIs aceptan texto libre):
// - "letras": solo letras, espacios, apostrofo, punto y guion; los digitos se descartan al tipear.
// - "digitos": solo numeros (DNI); el resto se descarta al tipear.
// - number: "min" y "step" impiden negativos; el signo "-" y la notacion "e" no se pueden tipear.
// - select: "value" es lo que se guarda (mismo formato que los datos iniciales de db/init-scripts)
//   y "label" lo que se ve, tanto en el desplegable como en la tabla.
const LETRAS = { pattern: "[\\p{L}' .\\-]+", title: 'Solo letras, sin números.', filtro: /\d/g };
const MONTO = { type: 'number', min: '0.01', step: '0.01', title: 'Un monto mayor a 0.' };

const ENTIDADES = [
  {
    key: 'clientes',
    titulo: 'Clientes',
    singular: 'el cliente',
    campos: [
      { name: 'nombre', label: 'Nombre', type: 'text', maxLength: 100, ...LETRAS },
      { name: 'email', label: 'Email', type: 'email', maxLength: 150 },
      {
        name: 'dni', label: 'DNI', type: 'text', inputMode: 'numeric', maxLength: 8,
        pattern: '\\d{7,8}', title: 'De 7 u 8 dígitos, sin puntos.', filtro: /\D/g,
      },
    ],
  },
  {
    key: 'pagos',
    titulo: 'Pagos',
    singular: 'el pago',
    campos: [
      { name: 'monto_ars', label: 'Monto (ARS)', ...MONTO },
      {
        name: 'medio_pago', label: 'Medio de pago', type: 'select',
        opciones: [
          { value: 'transferencia', label: 'Transferencia' },
          { value: 'tarjeta_debito', label: 'Tarjeta de Débito' },
          { value: 'tarjeta_credito', label: 'Tarjeta de Crédito' },
          { value: 'efectivo', label: 'Efectivo' },
        ],
      },
    ],
    soloLectura: [{ name: 'monto_usd', label: 'Monto (USD)' }],
  },
  {
    key: 'facturas',
    titulo: 'Facturas',
    singular: 'la factura',
    campos: [
      {
        name: 'numero', label: 'Número', type: 'text', maxLength: 30, placeholder: 'A-0001',
        pattern: '[A-Za-z]-\\d{4,8}', title: 'Letra, guion y de 4 a 8 dígitos. Ej.: A-0001',
      },
      { name: 'monto', label: 'Monto', ...MONTO },
      { name: 'clienteId', label: 'ID de cliente', type: 'number', min: '1', step: '1', title: 'Un ID entero mayor a 0.' },
      { name: 'fechaEmision', label: 'Fecha de emisión', type: 'date' },
    ],
  },
  {
    key: 'transacciones',
    titulo: 'Transacciones',
    singular: 'la transacción',
    campos: [
      {
        name: 'origen_ip', label: 'IP de origen', type: 'text', maxLength: 45, placeholder: '8.8.8.8',
        // IPv4 (cada octeto de 0 a 255) o IPv6 (hexadecimal con ":").
        pattern: '((25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)|[0-9A-Fa-f]{0,4}(:[0-9A-Fa-f]{0,4}){2,7}',
        title: 'Una dirección IPv4 (ej.: 8.8.8.8) o IPv6.',
      },
      { name: 'monto', label: 'Monto', ...MONTO },
      {
        name: 'tipo', label: 'Tipo', type: 'select',
        opciones: [
          { value: 'compra', label: 'Compra' },
          { value: 'retiro', label: 'Retiro' },
          { value: 'deposito', label: 'Depósito' },
          { value: 'transferencia', label: 'Transferencia' },
        ],
      },
    ],
    soloLectura: [{ name: 'pais', label: 'País' }],
  },
  {
    key: 'tarjetas',
    titulo: 'Tarjetas',
    singular: 'la tarjeta',
    campos: [
      { name: 'alias', label: 'Alias', type: 'text', maxLength: 50, ...LETRAS },
      { name: 'titular', label: 'Titular', type: 'text', maxLength: 100, ...LETRAS },
      {
        name: 'tipo', label: 'Tipo', type: 'select',
        opciones: [
          { value: 'credito', label: 'Crédito' },
          { value: 'debito', label: 'Débito' },
        ],
      },
      { name: 'limite', label: 'Límite', type: 'number', min: '0', step: '0.01', title: 'Un monto de 0 o más.' },
    ],
  },
];

// Valor guardado -> texto legible. Si el valor no esta entre las opciones (datos cargados por
// otro medio), se muestra igual, sin "_" y con mayuscula inicial: "tarjeta_debito" -> "Tarjeta debito".
function textoDeOpcion(campo, valor) {
  const opcion = campo.opciones.find((o) => o.value === valor);
  if (opcion) return opcion.label;
  const texto = String(valor).replace(/_/g, ' ');
  return texto.charAt(0).toUpperCase() + texto.slice(1);
}

// Crea el control de un campo del formulario con sus restricciones.
function crearControl(campo, id) {
  if (campo.type === 'select') {
    return el('select', { id, name: campo.name, required: true }, [
      el('option', { value: '', disabled: true, defaultSelected: true, text: 'Seleccioná…' }),
      ...campo.opciones.map((o) => el('option', { value: o.value, text: o.label })),
    ]);
  }
  const props = { id, type: campo.type, name: campo.name, required: true };
  ['min', 'step', 'pattern', 'title', 'maxLength', 'inputMode', 'placeholder'].forEach((k) => {
    if (campo[k] !== undefined) props[k] = campo[k];
  });
  const input = el('input', props);
  if (campo.filtro) {
    // Al tipear o pegar se descartan los caracteres no permitidos (digitos en un nombre, letras en el DNI).
    input.addEventListener('input', () => {
      const limpio = input.value.replace(campo.filtro, '');
      if (limpio !== input.value) input.value = limpio;
    });
  }
  if (campo.type === 'number') {
    // Un input number acepta "-", "+" y "e" (notacion cientifica): se bloquean al tipear. Si se pegan,
    // "min" hace que el navegador rechace el valor al enviar.
    const prohibidas = campo.step === '1' ? ['-', '+', 'e', 'E', '.', ','] : ['-', '+', 'e', 'E'];
    input.addEventListener('keydown', (e) => {
      if (prohibidas.includes(e.key)) e.preventDefault();
    });
  }
  return input;
}

const app = document.querySelector('#app');

// Atajo para crear elementos: el texto siempre va por textContent, nunca por innerHTML.
function el(tag, props = {}, hijos = []) {
  const nodo = document.createElement(tag);
  Object.entries(props).forEach(([k, v]) => {
    if (k === 'className') nodo.className = v;
    else if (k === 'text') nodo.textContent = v;
    else if (k in nodo && !k.startsWith('aria-') && !k.startsWith('data-')) nodo[k] = v;
    else nodo.setAttribute(k, v);
  });
  nodo.append(...hijos);
  return nodo;
}

// ---------------------------------------------------------------------------------------------
// Pestañas
// ---------------------------------------------------------------------------------------------
function crearNav() {
  const nav = el('nav', { 'aria-label': 'Entidades' });
  const lista = el('div', { className: 'tabs', role: 'tablist' });
  ENTIDADES.forEach((entidad, i) => {
    const btn = el('button', {
      type: 'button',
      id: `tab-${entidad.key}`,
      role: 'tab',
      'aria-controls': `panel-${entidad.key}`,
      'aria-selected': String(i === 0),
      tabIndex: i === 0 ? 0 : -1,
      'data-key': entidad.key,
    }, [
      el('span', { text: entidad.titulo }),
      el('span', { className: 'tab-contador', 'aria-hidden': 'true', text: '–' }),
    ]);
    btn.addEventListener('click', () => mostrarSeccion(entidad.key));
    lista.appendChild(btn);
  });
  // Flechas izquierda/derecha para moverse entre pestañas (patron de tabs de WAI-ARIA).
  lista.addEventListener('keydown', (e) => {
    if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
    const actual = ENTIDADES.findIndex((x) => x.key === document.activeElement.dataset.key);
    if (actual < 0) return;
    const paso = e.key === 'ArrowRight' ? 1 : -1;
    const siguiente = ENTIDADES[(actual + paso + ENTIDADES.length) % ENTIDADES.length];
    mostrarSeccion(siguiente.key);
    document.getElementById(`tab-${siguiente.key}`).focus();
  });
  nav.appendChild(lista);
  return nav;
}

function mostrarSeccion(key) {
  document.querySelectorAll('main section').forEach((s) => {
    s.hidden = s.dataset.key !== key;
  });
  document.querySelectorAll('[role="tab"]').forEach((b) => {
    const activa = b.dataset.key === key;
    b.setAttribute('aria-selected', String(activa));
    b.tabIndex = activa ? 0 : -1;
  });
}

// ---------------------------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------------------------
// fetch solo falla si no hay red: un 400, 429 o 502 llega como respuesta normal. Aca se convierte
// en error para no tratar un rechazo de la API como si fuera un exito.
async function pedir(url, opciones) {
  const res = await fetch(url, opciones);
  if (!res.ok) {
    const err = new Error(`HTTP ${res.status}`);
    err.status = res.status;
    throw err;
  }
  return res;
}

function avisar(section, mensaje) {
  const aviso = section.querySelector('.error');
  aviso.textContent = mensaje;
  aviso.hidden = !mensaje;
}

function actualizarContador(entidad, cantidad) {
  const texto = cantidad === 1 ? '1 registro' : `${cantidad} registros`;
  document.querySelector(`section[data-key="${entidad.key}"] .contador`).textContent = texto;
  document.querySelector(`#tab-${entidad.key} .tab-contador`).textContent = String(cantidad);
}

// ---------------------------------------------------------------------------------------------
// Seccion de cada entidad: formulario de alta/modificacion + tabla con modificacion y baja
// ---------------------------------------------------------------------------------------------

// Normaliza un valor para comparar el formulario con el registro guardado (ej.: 1500.5 y "1500.50").
function normalizarValor(campo, valor) {
  if (valor === null || valor === undefined) return '';
  if (campo.type === 'number') return String(Number(valor));
  if (campo.type === 'date') return String(valor).slice(0, 10);
  return String(valor);
}

// Si no cambio ningun campo editable, no se envia el PUT.
function hayCambios(entidad, original, datos) {
  return entidad.campos.some((campo) =>
    normalizarValor(campo, original[campo.name]) !== normalizarValor(campo, datos[campo.name]));
}

function crearFormulario(entidad, section, alGuardar) {
  const campos = el('div', { className: 'campos' });
  entidad.campos.forEach((campo) => {
    const id = `${entidad.key}-${campo.name}`;
    campos.appendChild(el('div', { className: 'campo' }, [
      el('label', { htmlFor: id, text: campo.label }),
      crearControl(campo, id),
    ]));
  });

  const titulo = el('h3', { text: 'Nuevo registro' });
  const cancelar = el('button', { type: 'button', className: 'btn btn-cancelar', text: 'Cancelar', hidden: true });
  const submit = el('button', { type: 'submit', className: 'btn btn-primario', text: 'Agregar' });
  const form = el('form', { className: 'tarjeta formulario', 'aria-label': `Alta de ${entidad.titulo.toLowerCase()}` }, [
    titulo,
    campos,
    el('div', { className: 'acciones' }, [cancelar, submit]),
  ]);

  // Registro que se esta modificando. Si es null, el formulario da de alta.
  let editando = null;
  const etiquetaBoton = () => (editando ? 'Guardar cambios' : 'Agregar');

  function salirDeEdicion() {
    editando = null;
    titulo.textContent = 'Nuevo registro';
    cancelar.hidden = true;
    form.classList.remove('en-edicion');
    submit.textContent = etiquetaBoton();
    form.reset();
  }

  // Carga el registro en el mismo formulario de alta, que pasa a modo modificacion.
  function editar(item) {
    editando = item;
    entidad.campos.forEach((campo) => {
      const valor = item[campo.name] ?? '';
      form.elements[campo.name].value = campo.type === 'date' ? String(valor).slice(0, 10) : valor;
    });
    titulo.textContent = `Editar registro #${item.id}`;
    cancelar.hidden = false;
    form.classList.add('en-edicion');
    submit.textContent = etiquetaBoton();
    form.scrollIntoView({ block: 'start' });
    form.elements[entidad.campos[0].name].focus();
  }

  cancelar.addEventListener('click', salirDeEdicion);

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const original = editando;
    const datos = Object.fromEntries(new FormData(form).entries());
    entidad.campos.forEach((campo) => {
      if (campo.type === 'number') datos[campo.name] = Number(datos[campo.name]);
    });
    if (original) {
      // El PUT de transacciones guarda "pais" desde el body y no lo recalcula: se reenvia el valor actual.
      if (entidad.key === 'transacciones') datos.pais = original.pais;
      if (!hayCambios(entidad, original, datos)) {
        salirDeEdicion();
        return;
      }
    }
    const url = original ? `/api/${entidad.key}/${original.id}` : `/api/${entidad.key}`;
    // Mientras viaja el pedido el boton queda deshabilitado: un doble clic no guarda dos veces.
    submit.disabled = true;
    submit.textContent = original ? 'Guardando cambios…' : 'Guardando…';
    try {
      await pedir(url, {
        method: original ? 'PUT' : 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(datos),
      });
    } catch (err) {
      if (original && err.status === 404) {
        // El registro se borro (por ejemplo desde otra pestana): se sale de la edicion y se recarga.
        // El aviso va despues de recargar, porque cargar() limpia los avisos al terminar.
        salirDeEdicion();
        await alGuardar();
        avisar(section, 'El registro ya no existe: se borró mientras lo editabas. Se recargó el listado.');
        return;
      }
      avisar(section, `No se pudo ${original ? 'modificar' : 'guardar'} (${err.message}). Revisá los datos e intentá de nuevo.`);
      return;
    } finally {
      submit.disabled = false;
      submit.textContent = etiquetaBoton();
    }
    salirDeEdicion();
    alGuardar();
  });
  return { form, editar };
}

function crearSeccion(entidad) {
  const section = el('section', {
    id: `panel-${entidad.key}`,
    role: 'tabpanel',
    'aria-labelledby': `tab-${entidad.key}`,
    'data-key': entidad.key,
  });
  section.hidden = entidad.key !== ENTIDADES[0].key;

  section.appendChild(el('div', { className: 'seccion-encabezado' }, [
    el('h2', { text: entidad.titulo }),
    el('span', { className: 'contador', text: 'Cargando…' }),
  ]));

  const columnas = [
    { name: 'id', label: 'ID' },
    ...entidad.campos,
    ...(entidad.soloLectura || []),
  ];

  const tbody = el('tbody');
  // "formulario" se crea antes que "recargar" porque "recargar" necesita su funcion "editar".
  const formulario = crearFormulario(entidad, section, () => recargar());
  const recargar = () => cargar(entidad, section, tbody, columnas, formulario.editar);

  section.appendChild(formulario.form);
  section.appendChild(el('p', { className: 'error', role: 'alert', hidden: true }));

  const trHead = el('tr', {}, [
    ...columnas.map((c) => el('th', { scope: 'col', text: c.label })),
    el('th', { scope: 'col' }, [el('span', { className: 'sr-only', text: 'Acciones' })]),
  ]);
  section.appendChild(el('div', { className: 'tarjeta tabla-contenedor' }, [
    el('table', {}, [el('thead', {}, [trHead]), tbody]),
  ]));

  filaMensaje(tbody, columnas, 'Cargando registros…');
  recargar();
  return section;
}

// Fila unica que ocupa todo el ancho: para "cargando" y "sin registros".
function filaMensaje(tbody, columnas, texto) {
  tbody.replaceChildren(el('tr', { className: 'fila-mensaje' }, [
    el('td', { colSpan: columnas.length + 1, text: texto }),
  ]));
}

async function cargar(entidad, section, tbody, columnas, alEditar) {
  let items;
  try {
    const res = await pedir(`/api/${entidad.key}`);
    items = await res.json();
  } catch (err) {
    avisar(section, `No se pudo cargar ${entidad.titulo} (${err.message}).`);
    filaMensaje(tbody, columnas, 'Sin datos disponibles.');
    section.querySelector('.contador').textContent = 'Sin conexión';
    return;
  }
  avisar(section, '');
  actualizarContador(entidad, items.length);
  if (items.length === 0) {
    filaMensaje(tbody, columnas, 'Todavía no hay registros. Cargá el primero con el formulario.');
    return;
  }
  tbody.replaceChildren();
  items.forEach((item) => {
    const tr = el('tr');
    columnas.forEach((col) => {
      const valor = item[col.name];
      const vacio = valor === null || valor === undefined || valor === '';
      let texto = valor;
      if (vacio) texto = '—';
      else if (col.opciones) texto = textoDeOpcion(col, valor);
      tr.appendChild(el('td', {
        className: vacio ? 'vacio' : '',
        'data-label': col.label,
        text: texto,
      }));
    });
    const btnEditar = el('button', {
      type: 'button',
      className: 'btn btn-secundario',
      text: 'Editar',
      'aria-label': `Editar ${entidad.singular} ${item.id}`,
    });
    btnEditar.addEventListener('click', () => alEditar(item));
    const btn = el('button', {
      type: 'button',
      className: 'btn btn-peligro',
      text: 'Borrar',
      'aria-label': `Borrar ${entidad.singular} ${item.id}`,
    });
    btn.addEventListener('click', async () => {
      if (!window.confirm(`¿Borrar ${entidad.singular} #${item.id}? Esta acción no se puede deshacer.`)) return;
      btn.disabled = true;
      try {
        await pedir(`/api/${entidad.key}/${item.id}`, { method: 'DELETE' });
      } catch (err) {
        btn.disabled = false;
        avisar(section, `No se pudo borrar (${err.message}).`);
        return;
      }
      cargar(entidad, section, tbody, columnas, alEditar);
    });
    tr.appendChild(el('td', { className: 'celda-accion' }, [btnEditar, btn]));
    tbody.appendChild(tr);
  });
}

// ---------------------------------------------------------------------------------------------
// Encabezado institucional de la aplicación
// ---------------------------------------------------------------------------------------------
function crearPortada() {
  const titulo = el('div', { className: 'marca' }, [
    el('span', { className: 'marca-logo', 'aria-hidden': 'true', text: 'N' }),
    el('div', {}, [
      el('h1', { text: 'FinTech Nova' }),
      el('p', { className: 'subtitulo', text: 'Panel de Microservicios' }),
    ]),
  ]);
  const contexto = el('p', {
    className: 'contexto',
    text: 'Arquitectura de Microservicios Políglotas · Docker · Despliegue Seguro en AWS EC2',
  });

  return el('header', {}, [
    el('div', { className: 'barra' }, [el('div', { className: 'contenedor barra-interior' }, [titulo, contexto])]),
  ]);
}

function render() {
  app.appendChild(crearPortada());
  const main = el('main', { className: 'contenedor' });
  main.appendChild(crearNav());
  ENTIDADES.forEach((entidad) => main.appendChild(crearSeccion(entidad)));
  app.appendChild(main);
}

render();
