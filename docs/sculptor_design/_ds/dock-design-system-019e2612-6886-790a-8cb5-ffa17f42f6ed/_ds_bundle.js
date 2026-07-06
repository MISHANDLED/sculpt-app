/* @ds-bundle: {"format":3,"namespace":"DockDesignSystem_019e26","components":[],"sourceHashes":{"ui_kits/blinkit-ops-console/DataTable.jsx":"bce28b71d34b","ui_kits/blinkit-ops-console/Drawer.jsx":"a6092450da9a","ui_kits/blinkit-ops-console/GlobalHeader.jsx":"c0fcdac36162","ui_kits/blinkit-ops-console/Modal.jsx":"07df1b426ae1","ui_kits/blinkit-ops-console/OrdersPage.jsx":"621048210016","ui_kits/blinkit-ops-console/Primitives.jsx":"598721f31a64","ui_kits/blinkit-ops-console/Sidebar.jsx":"d0d8c5b1c5ba","ui_kits/blinkit-ops-console/Toast.jsx":"97880f862866"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.DockDesignSystem_019e26 = window.DockDesignSystem_019e26 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// ui_kits/blinkit-ops-console/DataTable.jsx
try { (() => {
/* global React, Tag, IconButton */
const {
  useState,
  useMemo
} = React;
function DataTable({
  columns,
  rows,
  onRowClick,
  selectedId
}) {
  const [sortKey, setSortKey] = useState(null);
  const [sortDir, setSortDir] = useState('asc');
  const sorted = useMemo(() => {
    if (!sortKey) return rows;
    return [...rows].sort((a, b) => {
      const av = a[sortKey],
        bv = b[sortKey];
      if (av === bv) return 0;
      const cmp = (av > bv ? 1 : -1) * (sortDir === 'asc' ? 1 : -1);
      return cmp;
    });
  }, [rows, sortKey, sortDir]);
  const toggleSort = key => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');else {
      setSortKey(key);
      setSortDir('asc');
    }
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--dock-surface-primary)',
      border: '1px solid var(--dock-border-secondary)',
      borderRadius: 12,
      overflow: 'hidden'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      overflowX: 'auto'
    }
  }, /*#__PURE__*/React.createElement("table", {
    style: {
      width: '100%',
      borderCollapse: 'collapse',
      fontFamily: 'Lexend',
      fontSize: 13,
      lineHeight: '18px'
    }
  }, /*#__PURE__*/React.createElement("thead", null, /*#__PURE__*/React.createElement("tr", {
    style: {
      background: 'var(--dock-surface-secondary)'
    }
  }, columns.map(col => /*#__PURE__*/React.createElement("th", {
    key: col.key,
    onClick: col.sortable ? () => toggleSort(col.key) : undefined,
    style: {
      textAlign: col.align || 'left',
      padding: '10px 16px',
      fontWeight: 500,
      fontSize: 11,
      color: 'var(--dock-text-tertiary)',
      textTransform: 'uppercase',
      letterSpacing: '0.05em',
      borderBottom: '1px solid var(--dock-border-secondary)',
      cursor: col.sortable ? 'pointer' : 'default',
      whiteSpace: 'nowrap',
      userSelect: 'none',
      width: col.width
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 4
    }
  }, col.label, col.sortable && /*#__PURE__*/React.createElement("i", {
    className: sortKey !== col.key ? '--dock-icon-unfold-more' : sortDir === 'asc' ? '--dock-icon-keyboard-arrow-up' : '--dock-icon-keyboard-arrow-down',
    style: {
      fontSize: 14,
      opacity: sortKey === col.key ? 1 : 0.5
    }
  })))))), /*#__PURE__*/React.createElement("tbody", null, sorted.map(row => /*#__PURE__*/React.createElement("tr", {
    key: row.id,
    onClick: () => onRowClick?.(row),
    onMouseEnter: e => e.currentTarget.style.background = row.id === selectedId ? 'var(--dock-grey-100)' : 'var(--dock-grey-50)',
    onMouseLeave: e => e.currentTarget.style.background = row.id === selectedId ? 'var(--dock-grey-100)' : 'transparent',
    style: {
      background: row.id === selectedId ? 'var(--dock-grey-100)' : 'transparent',
      cursor: 'pointer',
      transition: 'background .12s'
    }
  }, columns.map(col => /*#__PURE__*/React.createElement("td", {
    key: col.key,
    style: {
      padding: '12px 16px',
      textAlign: col.align || 'left',
      borderBottom: '0.5px solid var(--dock-border-secondary)',
      color: 'var(--dock-text-primary)',
      fontVariantNumeric: col.numeric ? 'tabular-nums' : 'normal'
    }
  }, col.render ? col.render(row[col.key], row) : row[col.key]))))))));
}

// Status pill helper
function StatusPill({
  status
}) {
  const map = {
    delivered: {
      color: 'green',
      label: 'Delivered'
    },
    pending: {
      color: 'yellow',
      label: 'Pending'
    },
    shipped: {
      color: 'blue',
      label: 'Shipped'
    },
    cancelled: {
      color: 'red',
      label: 'Cancelled'
    },
    returned: {
      color: 'orange',
      label: 'Returned'
    }
  };
  const m = map[status] || map.pending;
  return /*#__PURE__*/React.createElement(Tag, {
    color: m.color
  }, m.label);
}
Object.assign(window, {
  DataTable,
  StatusPill
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/blinkit-ops-console/DataTable.jsx", error: String((e && e.message) || e) }); }

// ui_kits/blinkit-ops-console/Drawer.jsx
try { (() => {
/* global React, IconButton, Button */
const {
  useEffect
} = React;
function Drawer({
  open,
  title,
  subtitle,
  onClose,
  children,
  footer,
  width = 480
}) {
  useEffect(() => {
    if (!open) return;
    const onKey = e => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose]);
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      zIndex: 200,
      background: 'var(--dock-surface-overlay)',
      opacity: open ? 1 : 0,
      pointerEvents: open ? 'auto' : 'none',
      transition: 'opacity .2s'
    },
    onClick: onClose
  }), /*#__PURE__*/React.createElement("aside", {
    style: {
      position: 'absolute',
      top: 0,
      right: 0,
      bottom: 0,
      width,
      zIndex: 201,
      background: 'var(--dock-surface-primary)',
      borderLeft: '1px solid var(--dock-border-primary)',
      boxShadow: 'var(--dock-shadow-2xl)',
      display: 'flex',
      flexDirection: 'column',
      transform: open ? 'translateX(0)' : `translateX(${width + 10}px)`,
      transition: 'transform .25s ease-in-out'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'flex-start',
      gap: 12,
      padding: '16px 20px',
      borderBottom: '1px solid var(--dock-border-secondary)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'Lexend',
      fontSize: 18,
      fontWeight: 600,
      lineHeight: '24px'
    }
  }, title), subtitle && /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'Lexend',
      fontSize: 13,
      color: 'var(--dock-text-tertiary)',
      marginTop: 2
    }
  }, subtitle)), /*#__PURE__*/React.createElement(IconButton, {
    icon: "close",
    onClick: onClose,
    title: "Close"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflowY: 'auto',
      padding: 20
    }
  }, children), footer && /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'flex-end',
      gap: 8,
      padding: '12px 20px',
      borderTop: '1px solid var(--dock-border-secondary)',
      background: 'var(--dock-surface-primary)'
    }
  }, footer)));
}
Object.assign(window, {
  Drawer
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/blinkit-ops-console/Drawer.jsx", error: String((e && e.message) || e) }); }

// ui_kits/blinkit-ops-console/GlobalHeader.jsx
try { (() => {
/* global React, BadgeTag, Input, IconButton, Avatar, Button, Kbd */
const {
  useState,
  useRef,
  useEffect
} = React;
function GlobalHeader({
  site,
  location,
  onChangeLocation,
  locations,
  onOpenSearch,
  onToggleTheme,
  theme,
  notificationCount,
  user
}) {
  const [locOpen, setLocOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const locRef = useRef(null),
    profileRef = useRef(null);
  useEffect(() => {
    const h = e => {
      if (locRef.current && !locRef.current.contains(e.target)) setLocOpen(false);
      if (profileRef.current && !profileRef.current.contains(e.target)) setProfileOpen(false);
    };
    document.addEventListener('mousedown', h);
    return () => document.removeEventListener('mousedown', h);
  }, []);
  return /*#__PURE__*/React.createElement("header", {
    style: {
      height: 53,
      flexShrink: 0,
      background: 'var(--dock-surface-primary)',
      borderBottom: '1px solid var(--dock-border-secondary)',
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      padding: '0 16px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement(BadgeTag, {
    label: "Site",
    value: site,
    color: "black"
  }), /*#__PURE__*/React.createElement("div", {
    ref: locRef,
    style: {
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("button", {
    onClick: () => setLocOpen(o => !o),
    onMouseEnter: e => e.currentTarget.style.color = 'var(--dock-grey-800)',
    onMouseLeave: e => e.currentTarget.style.color = 'var(--dock-text-primary)',
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 8,
      padding: '0',
      height: 36,
      background: 'transparent',
      border: 0,
      fontFamily: 'Lexend',
      fontSize: 14,
      lineHeight: '18px',
      fontWeight: 500,
      color: 'var(--dock-text-primary)',
      cursor: 'pointer',
      transition: 'color .15s'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      borderBottom: '1px dashed currentColor',
      paddingBottom: 2
    }
  }, location), /*#__PURE__*/React.createElement("i", {
    className: locOpen ? '--dock-icon-keyboard-arrow-up' : '--dock-icon-keyboard-arrow-down',
    style: {
      fontSize: 18
    }
  })), locOpen && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top: 'calc(100% + 4px)',
      left: 0,
      minWidth: 280,
      zIndex: 100,
      background: 'var(--dock-surface-primary)',
      border: '1px solid var(--dock-border-primary)',
      borderRadius: 8,
      boxShadow: 'var(--dock-shadow-md)',
      padding: 4
    }
  }, locations.map(l => /*#__PURE__*/React.createElement("button", {
    key: l,
    onClick: () => {
      onChangeLocation(l);
      setLocOpen(false);
    },
    onMouseEnter: e => e.currentTarget.style.background = 'var(--dock-surface-secondary)',
    onMouseLeave: e => e.currentTarget.style.background = l === location ? 'var(--dock-surface-secondary)' : 'transparent',
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      width: '100%',
      padding: '10px 12px',
      borderRadius: 4,
      border: 0,
      background: l === location ? 'var(--dock-surface-secondary)' : 'transparent',
      fontFamily: 'Lexend',
      fontSize: 14,
      lineHeight: '18px',
      cursor: 'pointer',
      textAlign: 'left',
      color: 'var(--dock-text-primary)',
      fontWeight: l === location ? 500 : 400
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }, l), l === location && /*#__PURE__*/React.createElement("i", {
    className: "--dock-icon-check",
    style: {
      fontSize: 16
    }
  }))))), /*#__PURE__*/React.createElement("div", {
    onClick: onOpenSearch,
    style: {
      width: 238,
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(Input, {
    placeholder: "\u2318+K to Search",
    leftIcon: "search-1",
    size: "md",
    value: "",
    readOnly: true
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      marginLeft: 'auto',
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "link-black",
    size: "sm"
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      borderBottom: '1px dashed currentColor',
      paddingBottom: 1
    }
  }, "Raise Ticket")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement(IconButton, {
    icon: "notifications",
    title: "Notifications"
  }), notificationCount > 0 && /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      top: 4,
      right: 4,
      minWidth: 16,
      height: 16,
      padding: '0 4px',
      background: 'var(--dock-red-600)',
      color: '#fff',
      borderRadius: 9999,
      fontSize: 9,
      fontWeight: 600,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, notificationCount)), /*#__PURE__*/React.createElement(IconButton, {
    icon: theme === 'dark' ? 'light-mode' : 'dark-mode',
    title: "Toggle theme",
    onClick: onToggleTheme
  }), /*#__PURE__*/React.createElement(IconButton, {
    icon: "contact-support-rounded",
    title: "Support"
  })), /*#__PURE__*/React.createElement("div", {
    ref: profileRef,
    style: {
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("button", {
    onClick: () => setProfileOpen(o => !o),
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      padding: '4px 8px 4px 4px',
      borderRadius: 9999,
      border: 0,
      background: 'transparent',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(Avatar, {
    initials: user.initials,
    color: user.color,
    size: 32
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      textAlign: 'left'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'Lexend',
      fontSize: 12,
      fontWeight: 500,
      lineHeight: '14px'
    }
  }, user.name), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'Lexend',
      fontSize: 10,
      color: 'var(--dock-text-tertiary)',
      lineHeight: '12px'
    }
  }, user.id)), /*#__PURE__*/React.createElement("i", {
    className: "--dock-icon-expand-more",
    style: {
      fontSize: 16,
      color: 'var(--dock-text-tertiary)'
    }
  })), profileOpen && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top: 'calc(100% + 4px)',
      right: 0,
      minWidth: 220,
      zIndex: 100,
      background: 'var(--dock-surface-primary)',
      border: '1px solid var(--dock-border-primary)',
      borderRadius: 8,
      boxShadow: 'var(--dock-shadow-lg)',
      padding: 4
    }
  }, /*#__PURE__*/React.createElement(ProfileItem, {
    icon: "account-circle",
    label: "My profile"
  }), /*#__PURE__*/React.createElement(ProfileItem, {
    icon: "settings",
    label: "Preferences"
  }), /*#__PURE__*/React.createElement(ProfileItem, {
    icon: "help",
    label: "Documentation",
    rightContent: /*#__PURE__*/React.createElement(Kbd, null, "?")
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 1,
      background: 'var(--dock-border-secondary)',
      margin: '4px 0'
    }
  }), /*#__PURE__*/React.createElement(ProfileItem, {
    icon: "logout",
    label: "Sign out",
    destructive: true
  })))));
}
function ProfileItem({
  icon,
  label,
  destructive,
  rightContent,
  onClick
}) {
  return /*#__PURE__*/React.createElement("button", {
    onClick: onClick,
    onMouseEnter: e => e.currentTarget.style.background = destructive ? 'var(--dock-red-50)' : 'var(--dock-grey-50)',
    onMouseLeave: e => e.currentTarget.style.background = 'transparent',
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      width: '100%',
      padding: '8px 10px',
      borderRadius: 6,
      border: 0,
      background: 'transparent',
      cursor: 'pointer',
      fontFamily: 'Lexend',
      fontSize: 13,
      textAlign: 'left',
      color: destructive ? 'var(--dock-text-error)' : 'var(--dock-text-primary)'
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${icon}`,
    style: {
      fontSize: 16
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }, label), rightContent);
}
Object.assign(window, {
  GlobalHeader
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/blinkit-ops-console/GlobalHeader.jsx", error: String((e && e.message) || e) }); }

// ui_kits/blinkit-ops-console/Modal.jsx
try { (() => {
/* global React, Button, IconButton */
const {
  useEffect
} = React;
function Modal({
  open,
  onClose,
  title,
  children,
  footer,
  icon = 'warning',
  iconColor = 'red'
}) {
  useEffect(() => {
    if (!open) return;
    const onKey = e => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose]);
  if (!open) return null;
  const iconBg = {
    red: ['var(--dock-red-100)', 'var(--dock-red-700)'],
    orange: ['var(--dock-orange-100)', 'var(--dock-orange-700)'],
    green: ['var(--dock-green-100)', 'var(--dock-green-700)'],
    blue: ['var(--dock-blue-100)', 'var(--dock-blue-700)']
  }[iconColor];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      zIndex: 300,
      background: 'var(--dock-surface-overlay)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: 24
    },
    onClick: onClose
  }, /*#__PURE__*/React.createElement("div", {
    onClick: e => e.stopPropagation(),
    style: {
      background: 'var(--dock-surface-primary)',
      borderRadius: 12,
      boxShadow: 'var(--dock-shadow-2xl)',
      width: 'min(440px, 100%)',
      display: 'flex',
      flexDirection: 'column'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '24px 24px 16px',
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 44,
      height: 44,
      borderRadius: 9999,
      background: iconBg[0],
      color: iconBg[1],
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      marginBottom: 16
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${icon}`,
    style: {
      fontSize: 22
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'Lexend',
      fontSize: 18,
      fontWeight: 600
    }
  }, title), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'Lexend',
      fontSize: 14,
      lineHeight: '20px',
      color: 'var(--dock-text-tertiary)',
      marginTop: 6
    }
  }, children), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top: 12,
      right: 12
    }
  }, /*#__PURE__*/React.createElement(IconButton, {
    icon: "close",
    onClick: onClose,
    title: "Close"
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'flex-end',
      gap: 8,
      padding: '0 24px 24px'
    }
  }, footer)));
}
Object.assign(window, {
  Modal
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/blinkit-ops-console/Modal.jsx", error: String((e && e.message) || e) }); }

// ui_kits/blinkit-ops-console/OrdersPage.jsx
try { (() => {
/* global React, Pill, Tag, Button, Input, IconButton, DataTable, StatusPill */
const {
  useState,
  useMemo
} = React;
const SAMPLE_ORDERS = [{
  id: 'BLK-29481',
  customer: 'Aanya R.',
  items: 7,
  total: 842,
  eta: '3 min',
  status: 'shipped',
  placed: '10:24',
  rider: 'Suresh K.'
}, {
  id: 'BLK-29480',
  customer: 'Karan M.',
  items: 3,
  total: 256,
  eta: 'Delivered',
  'status': 'delivered',
  placed: '10:22',
  rider: 'Anil V.'
}, {
  id: 'BLK-29479',
  customer: 'Priya S.',
  items: 12,
  total: 1684,
  eta: '7 min',
  status: 'pending',
  placed: '10:21',
  rider: '—'
}, {
  id: 'BLK-29478',
  customer: 'Vikram D.',
  items: 5,
  total: 489,
  eta: 'Delivered',
  'status': 'delivered',
  placed: '10:19',
  rider: 'Anil V.'
}, {
  id: 'BLK-29477',
  customer: 'Meera P.',
  items: 2,
  total: 178,
  eta: '—',
  status: 'cancelled',
  placed: '10:18',
  rider: '—'
}, {
  id: 'BLK-29476',
  customer: 'Rohan G.',
  items: 9,
  total: 1245,
  eta: '12 min',
  status: 'shipped',
  placed: '10:16',
  rider: 'Pavan T.'
}, {
  id: 'BLK-29475',
  customer: 'Sneha L.',
  items: 1,
  total: 89,
  eta: 'Delivered',
  'status': 'delivered',
  placed: '10:14',
  rider: 'Pavan T.'
}, {
  id: 'BLK-29474',
  customer: 'Arjun B.',
  items: 6,
  total: 612,
  eta: 'Returned',
  'status': 'returned',
  placed: '10:12',
  rider: 'Suresh K.'
}, {
  id: 'BLK-29473',
  customer: 'Neha I.',
  items: 4,
  total: 398,
  eta: '5 min',
  status: 'shipped',
  placed: '10:10',
  rider: 'Anil V.'
}, {
  id: 'BLK-29472',
  customer: 'Ishaan T.',
  items: 8,
  total: 944,
  eta: 'Delivered',
  'status': 'delivered',
  placed: '10:09',
  rider: 'Pavan T.'
}];
function KPI({
  label,
  value,
  delta,
  deltaPositive = true,
  icon
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 180,
      background: 'var(--dock-surface-primary)',
      border: '1px solid var(--dock-border-secondary)',
      borderRadius: 12,
      padding: 16
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      color: 'var(--dock-text-tertiary)',
      fontSize: 12,
      fontWeight: 500,
      textTransform: 'uppercase',
      letterSpacing: '0.04em'
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${icon}`,
    style: {
      fontSize: 14
    }
  }), label), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 10,
      display: 'flex',
      alignItems: 'baseline',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'Lexend',
      fontSize: 28,
      fontWeight: 600,
      lineHeight: '36px',
      letterSpacing: '-0.01em'
    }
  }, value), delta && /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 2,
      fontSize: 12,
      fontWeight: 500,
      lineHeight: '16px',
      color: deltaPositive ? 'var(--dock-text-success)' : 'var(--dock-text-error)'
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: deltaPositive ? '--dock-icon-trending-up' : '--dock-icon-trending-down',
    style: {
      fontSize: 14
    }
  }), delta)));
}
function OrdersPage({
  orders,
  onRowClick,
  selectedId,
  filter,
  onFilterChange
}) {
  const counts = useMemo(() => {
    const c = {
      all: orders.length,
      pending: 0,
      shipped: 0,
      delivered: 0,
      cancelled: 0
    };
    orders.forEach(o => {
      if (c[o.status] != null) c[o.status]++;
    });
    return c;
  }, [orders]);
  const visible = useMemo(() => filter === 'all' ? orders : orders.filter(o => o.status === filter), [orders, filter]);
  const columns = [{
    key: 'id',
    label: 'Order ID',
    sortable: true,
    width: 140
  }, {
    key: 'customer',
    label: 'Customer',
    sortable: true
  }, {
    key: 'items',
    label: 'Items',
    sortable: true,
    numeric: true,
    align: 'right',
    width: 70
  }, {
    key: 'total',
    label: 'Total',
    sortable: true,
    numeric: true,
    align: 'right',
    width: 100,
    render: v => `₹${v.toLocaleString('en-IN')}`
  }, {
    key: 'placed',
    label: 'Placed',
    sortable: true,
    width: 100,
    render: v => /*#__PURE__*/React.createElement("span", {
      style: {
        color: 'var(--dock-text-tertiary)'
      }
    }, v)
  }, {
    key: 'rider',
    label: 'Rider',
    width: 140,
    render: v => v === '—' ? /*#__PURE__*/React.createElement("span", {
      style: {
        color: 'var(--dock-text-quaternary)'
      }
    }, v) : v
  }, {
    key: 'eta',
    label: 'ETA',
    width: 100,
    render: v => v === 'Delivered' || v === 'Returned' || v === '—' ? /*#__PURE__*/React.createElement("span", {
      style: {
        color: 'var(--dock-text-quaternary)'
      }
    }, v) : /*#__PURE__*/React.createElement("span", {
      style: {
        fontWeight: 500
      }
    }, v)
  }, {
    key: 'status',
    label: 'Status',
    sortable: true,
    width: 130,
    render: v => /*#__PURE__*/React.createElement(StatusPill, {
      status: v
    })
  }, {
    key: '_act',
    label: '',
    width: 40,
    align: 'right',
    render: (_, row) => /*#__PURE__*/React.createElement(IconButton, {
      icon: "3-dot-horizontal",
      size: "sm",
      title: "More",
      onClick: e => e.stopPropagation()
    })
  }];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 24,
      display: 'flex',
      flexDirection: 'column',
      gap: 16,
      height: '100%',
      overflow: 'auto'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'flex-start',
      justifyContent: 'space-between',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'Lexend',
      fontSize: 24,
      fontWeight: 600,
      lineHeight: '30px'
    }
  }, "Live orders"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'Lexend',
      fontSize: 13,
      color: 'var(--dock-text-tertiary)',
      marginTop: 2
    }
  }, "Real-time order queue. Click any row for details.")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    leftIcon: "download"
  }, "Export"), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    leftIcon: "add"
  }, "New order"))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 12,
      flexWrap: 'wrap'
    }
  }, /*#__PURE__*/React.createElement(KPI, {
    label: "Orders today",
    value: "12,481",
    delta: "+8.2%",
    icon: "shopping-cart"
  }), /*#__PURE__*/React.createElement(KPI, {
    label: "Avg basket",
    value: "\u20B9442",
    delta: "+\u20B914",
    icon: "trending-up"
  }), /*#__PURE__*/React.createElement(KPI, {
    label: "Delivery SLA",
    value: "99.2%",
    delta: "\u22120.4%",
    deltaPositive: false,
    icon: "schedule"
  }), /*#__PURE__*/React.createElement(KPI, {
    label: "Active riders",
    value: "284",
    delta: "+12",
    icon: "delivery-truck"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      padding: '12px 0'
    }
  }, /*#__PURE__*/React.createElement(Pill, {
    active: filter === 'all',
    onClick: () => onFilterChange('all'),
    count: counts.all,
    size: "sm"
  }, "All"), /*#__PURE__*/React.createElement(Pill, {
    active: filter === 'pending',
    onClick: () => onFilterChange('pending'),
    count: counts.pending,
    size: "sm"
  }, "Pending"), /*#__PURE__*/React.createElement(Pill, {
    active: filter === 'shipped',
    onClick: () => onFilterChange('shipped'),
    count: counts.shipped,
    size: "sm"
  }, "Out for delivery"), /*#__PURE__*/React.createElement(Pill, {
    active: filter === 'delivered',
    onClick: () => onFilterChange('delivered'),
    count: counts.delivered,
    size: "sm"
  }, "Delivered"), /*#__PURE__*/React.createElement(Pill, {
    active: filter === 'cancelled',
    onClick: () => onFilterChange('cancelled'),
    count: counts.cancelled,
    size: "sm"
  }, "Cancelled"), /*#__PURE__*/React.createElement("div", {
    style: {
      marginLeft: 'auto',
      display: 'flex',
      gap: 8,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "ghost-black",
    leftIcon: "filter-list",
    size: "sm"
  }, "Filters"), /*#__PURE__*/React.createElement(Button, {
    variant: "ghost-black",
    leftIcon: "sort",
    size: "sm"
  }, "Sort"))), /*#__PURE__*/React.createElement(DataTable, {
    columns: columns,
    rows: visible,
    onRowClick: onRowClick,
    selectedId: selectedId
  }), visible.length === 0 && /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 40,
      textAlign: 'center',
      background: 'var(--dock-surface-secondary)',
      border: '1px solid var(--dock-border-secondary)',
      borderRadius: 12,
      color: 'var(--dock-text-tertiary)'
    }
  }, "No orders in this state."));
}
Object.assign(window, {
  OrdersPage,
  KPI,
  SAMPLE_ORDERS
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/blinkit-ops-console/OrdersPage.jsx", error: String((e && e.message) || e) }); }

// ui_kits/blinkit-ops-console/Primitives.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* global React */
/* ============================================================================
 * Primitives — Button, IconButton, Pill, Tag, Input, Avatar, Spinner
 * Every visual constant lives in --dock-* CSS vars; the JSX only composes.
 * ========================================================================= */

const {
  useEffect,
  useRef,
  useState
} = React;

// ---- Button -----------------------------------------------------------------
function Button({
  variant = 'primary',
  buttonType = 'default',
  size = 'md',
  shape = 'square',
  leftIcon,
  rightIcon,
  iconOnly,
  isLoading,
  disabled,
  fullWidth,
  children,
  onClick,
  ...rest
}) {
  const sizes = {
    sm: {
      h: 28,
      px: 8,
      fs: 12,
      lh: 16,
      gap: 6,
      r: 4
    },
    md: {
      h: 36,
      px: 10,
      fs: 14,
      lh: 18,
      gap: 8,
      r: 6
    },
    lg: {
      h: 48,
      px: 16,
      fs: 18,
      lh: 24,
      gap: 8,
      r: 8
    }
  };
  const sz = sizes[size];
  const isDestructive = buttonType === 'destructive';

  // Resolve bg/fg/border by variant + buttonType
  let bg = 'transparent',
    fg = 'var(--dock-text-primary)',
    border = '0';
  if (variant === 'primary') {
    bg = isDestructive ? 'var(--dock-red-600)' : 'var(--dock-surface-dark-intense)';
    fg = 'var(--dock-text-only-white)';
  } else if (variant === 'secondary') {
    bg = 'var(--dock-surface-primary)';
    fg = isDestructive ? 'var(--dock-red-600)' : 'var(--dock-text-primary)';
    border = `1px solid ${isDestructive ? 'var(--dock-red-600)' : 'var(--dock-text-primary)'}`;
  } else if (variant === 'ghost-black') {
    fg = isDestructive ? 'var(--dock-red-600)' : 'var(--dock-text-primary)';
  } else if (variant === 'ghost-blue') {
    fg = isDestructive ? 'var(--dock-red-600)' : 'var(--dock-blue-600)';
  } else if (variant === 'link-black') {
    fg = isDestructive ? 'var(--dock-red-600)' : 'var(--dock-text-primary)';
  } else if (variant === 'link-blue') {
    fg = isDestructive ? 'var(--dock-red-600)' : 'var(--dock-blue-600)';
  }
  if (disabled) {
    bg = variant === 'primary' ? 'var(--dock-grey-200)' : variant === 'secondary' ? 'transparent' : bg;
    fg = 'var(--dock-grey-400)';
    if (variant === 'secondary') border = '1px solid var(--dock-grey-300)';
  }
  const isIconOnly = !!iconOnly;
  const padX = isIconOnly ? 0 : sz.px;
  const width = isIconOnly ? sz.h : undefined;
  return /*#__PURE__*/React.createElement("button", _extends({
    onClick: onClick,
    disabled: disabled || isLoading,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: sz.gap,
      height: sz.h,
      width: width || (fullWidth ? '100%' : undefined),
      padding: `0 ${padX}px`,
      background: bg,
      color: fg,
      border,
      borderRadius: shape === 'circle' ? 9999 : sz.r,
      fontFamily: 'Lexend',
      fontWeight: 500,
      fontSize: sz.fs,
      lineHeight: `${sz.lh}px`,
      cursor: disabled ? 'not-allowed' : 'pointer',
      transition: 'all .2s',
      userSelect: 'none',
      whiteSpace: 'nowrap'
    },
    onMouseEnter: e => {
      if (disabled || isLoading) return;
      if (variant === 'primary' && !isDestructive) e.currentTarget.style.background = 'var(--dock-grey-800)';
      if (variant === 'primary' && isDestructive) e.currentTarget.style.background = 'var(--dock-red-700)';
      if (variant === 'secondary' && !isDestructive) e.currentTarget.style.background = 'var(--dock-grey-50)';
      if (variant === 'secondary' && isDestructive) e.currentTarget.style.background = 'var(--dock-red-50)';
      if (variant === 'ghost-black') e.currentTarget.style.background = 'var(--dock-grey-50)';
    },
    onMouseLeave: e => {
      e.currentTarget.style.background = bg;
    }
  }, rest), isLoading && /*#__PURE__*/React.createElement(Spinner, {
    size: sz.fs - 2,
    color: fg
  }), !isLoading && leftIcon && /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${leftIcon}`,
    style: {
      fontSize: sz.fs + 2
    }
  }), !isLoading && iconOnly && /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${iconOnly}`,
    style: {
      fontSize: sz.fs + 2
    }
  }), !iconOnly && children, !isLoading && rightIcon && /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${rightIcon}`,
    style: {
      fontSize: sz.fs + 2
    }
  }));
}

// ---- Spinner ----------------------------------------------------------------
function Spinner({
  size = 14,
  color = 'currentColor'
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-block',
      width: size,
      height: size,
      border: `2px solid ${color}`,
      borderTopColor: 'transparent',
      borderRadius: '50%',
      animation: 'dockSpin 0.7s linear infinite'
    }
  });
}

// ---- IconButton (ghost circular) -------------------------------------------
function IconButton({
  icon,
  onClick,
  title,
  color,
  size = 'md'
}) {
  const dim = size === 'sm' ? 28 : size === 'lg' ? 48 : 36;
  const fs = size === 'sm' ? 16 : size === 'lg' ? 22 : 18;
  return /*#__PURE__*/React.createElement("button", {
    onClick: onClick,
    title: title,
    onMouseEnter: e => e.currentTarget.style.background = 'var(--dock-grey-50)',
    onMouseLeave: e => e.currentTarget.style.background = 'transparent',
    style: {
      width: dim,
      height: dim,
      borderRadius: 6,
      border: 0,
      background: 'transparent',
      color: color || 'var(--dock-text-primary)',
      cursor: 'pointer',
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      transition: 'background .15s'
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${icon}`,
    style: {
      fontSize: fs
    }
  }));
}

// ---- Pill -------------------------------------------------------------------
function Pill({
  children,
  active,
  leftIcon,
  count,
  size = 'md',
  onClick
}) {
  const sizes = {
    sm: {
      px: 8,
      py: 6,
      fs: 12,
      gap: 4
    },
    md: {
      px: 10,
      py: 8,
      fs: 14,
      gap: 6
    }
  };
  const sz = sizes[size];
  return /*#__PURE__*/React.createElement("button", {
    onClick: onClick,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: sz.gap,
      padding: `${sz.py}px ${sz.px}px`,
      borderRadius: 9999,
      background: active ? 'var(--dock-surface-dark-intense)' : 'var(--dock-grey-200)',
      color: active ? 'var(--dock-text-only-white)' : 'var(--dock-text-primary)',
      border: 0,
      fontFamily: 'Lexend',
      fontSize: sz.fs,
      fontWeight: 500,
      cursor: onClick ? 'pointer' : 'default',
      transition: 'all .2s'
    }
  }, leftIcon && /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${leftIcon}`,
    style: {
      fontSize: sz.fs + 2
    }
  }), children, count != null && /*#__PURE__*/React.createElement("span", {
    style: {
      minWidth: 20,
      height: 20,
      padding: '0 6px',
      borderRadius: 9999,
      background: active ? 'var(--dock-surface-primary)' : 'var(--dock-grey-dark-950)',
      color: active ? 'var(--dock-text-primary)' : 'var(--dock-text-only-white)',
      fontSize: 10,
      fontWeight: 500,
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, count));
}

// ---- Tag (status chip) ------------------------------------------------------
const TAG_COLORS = {
  grey: {
    primary: ['var(--dock-grey-600)', '#fff'],
    secondary: ['var(--dock-grey-200)', 'var(--dock-grey-900)']
  },
  green: {
    primary: ['var(--dock-green-600)', '#fff'],
    secondary: ['var(--dock-green-100)', 'var(--dock-green-900)']
  },
  blue: {
    primary: ['var(--dock-blue-600)', '#fff'],
    secondary: ['var(--dock-blue-100)', 'var(--dock-blue-900)']
  },
  red: {
    primary: ['var(--dock-red-600)', '#fff'],
    secondary: ['var(--dock-red-100)', 'var(--dock-red-900)']
  },
  orange: {
    primary: ['var(--dock-orange-600)', '#fff'],
    secondary: ['var(--dock-orange-100)', 'var(--dock-orange-900)']
  },
  yellow: {
    primary: ['var(--dock-yellow-600)', 'var(--dock-black-light)'],
    secondary: ['var(--dock-yellow-100)', 'var(--dock-yellow-900)']
  },
  purple: {
    primary: ['var(--dock-purple-600)', '#fff'],
    secondary: ['var(--dock-purple-100)', 'var(--dock-purple-900)']
  },
  black: {
    primary: ['var(--dock-grey-dark-950)', '#fff'],
    secondary: ['var(--dock-grey-dark-950)', '#fff']
  }
};
function Tag({
  children,
  color = 'grey',
  variant = 'secondary',
  leftIcon,
  size = 'md'
}) {
  const [bg, fg] = TAG_COLORS[color][variant];
  const fs = size === 'sm' ? 11 : 12;
  const pad = size === 'sm' ? '2px 6px' : '4px 6px';
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 4,
      padding: pad,
      borderRadius: 4,
      background: bg,
      color: fg,
      fontFamily: 'Lexend',
      fontSize: fs,
      fontWeight: 500,
      lineHeight: '16px',
      whiteSpace: 'nowrap'
    }
  }, leftIcon && /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${leftIcon}`,
    style: {
      fontSize: fs + 2
    }
  }), children);
}

// ---- Badge Tag (label + value) ---------------------------------------------
function BadgeTag({
  label,
  value,
  color = 'black'
}) {
  const [bg, fg] = TAG_COLORS[color].primary;
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 4,
      paddingLeft: 8,
      paddingRight: 2,
      padding: '2px 2px 2px 8px',
      borderRadius: 4,
      background: bg,
      color: fg,
      fontFamily: 'Lexend',
      fontSize: 12,
      fontWeight: 500,
      lineHeight: '16px'
    }
  }, label, /*#__PURE__*/React.createElement("span", {
    style: {
      background: 'var(--dock-grey-50)',
      color: 'var(--dock-grey-900)',
      padding: '2px 6px',
      borderRadius: 2,
      fontWeight: 500,
      letterSpacing: '0.02em'
    }
  }, value));
}

// ---- Input ------------------------------------------------------------------
function Input({
  leftIcon,
  rightIcon,
  value,
  onChange,
  placeholder,
  size = 'md',
  state = 'default',
  clearable,
  fullWidth,
  readOnly,
  autoFocus
}) {
  const [focused, setFocused] = useState(false);
  const ref = useRef(null);
  useEffect(() => {
    if (autoFocus && ref.current) ref.current.focus();
  }, [autoFocus]);
  const sz = size === 'lg' ? {
    h: 48,
    pad: 12,
    r: 8,
    fs: 16
  } : {
    h: 36,
    pad: 8,
    r: 6,
    fs: 14
  };
  const borderColor = state === 'error' ? 'var(--dock-red-600)' : state === 'success' ? 'var(--dock-green-600)' : focused ? 'var(--dock-border-dark)' : 'var(--dock-border-primary)';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      height: sz.h,
      padding: sz.pad,
      borderRadius: sz.r,
      background: 'var(--dock-surface-primary)',
      border: `1px solid ${borderColor}`,
      transition: 'all .15s',
      width: fullWidth ? '100%' : 'auto',
      boxShadow: focused ? '0 0 0 1px var(--dock-border-light), 0 0 0 3px var(--dock-border-alpha-dark-normal)' : 'none'
    }
  }, leftIcon && /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${leftIcon}`,
    style: {
      color: 'var(--dock-icon-tertiary)',
      fontSize: sz.fs + 2
    }
  }), /*#__PURE__*/React.createElement("input", {
    ref: ref,
    value: value,
    onChange: e => onChange?.(e.target.value),
    placeholder: placeholder,
    readOnly: readOnly,
    onFocus: () => setFocused(true),
    onBlur: () => setFocused(false),
    style: {
      flex: 1,
      minWidth: 0,
      border: 0,
      outline: 0,
      background: 'transparent',
      fontFamily: 'Lexend',
      fontSize: sz.fs,
      lineHeight: '20px',
      color: 'var(--dock-text-primary)'
    }
  }), clearable && value && /*#__PURE__*/React.createElement("i", {
    className: "--dock-icon-close",
    onClick: () => onChange?.(''),
    style: {
      color: 'var(--dock-text-tertiary)',
      cursor: 'pointer',
      fontSize: sz.fs + 2
    }
  }), rightIcon && /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${rightIcon}`,
    style: {
      color: 'var(--dock-icon-tertiary)',
      fontSize: sz.fs + 2
    }
  }));
}

// ---- Avatar -----------------------------------------------------------------
function Avatar({
  initials,
  color = 'purple',
  size = 32
}) {
  const colors = {
    purple: ['var(--dock-purple-100)', 'var(--dock-purple-900)'],
    teal: ['var(--dock-teal-100)', 'var(--dock-teal-900)'],
    orange: ['var(--dock-orange-100)', 'var(--dock-orange-900)'],
    blue: ['var(--dock-blue-100)', 'var(--dock-blue-900)'],
    pink: ['var(--dock-pink-100)', 'var(--dock-pink-900)']
  };
  const [bg, fg] = colors[color] || colors.purple;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width: size,
      height: size,
      borderRadius: 9999,
      background: bg,
      color: fg,
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontFamily: 'Lexend',
      fontSize: Math.round(size * 0.4),
      fontWeight: 600,
      flexShrink: 0
    }
  }, initials);
}

// ---- Kbd --------------------------------------------------------------------
function Kbd({
  children
}) {
  return /*#__PURE__*/React.createElement("kbd", {
    style: {
      fontFamily: 'Lexend',
      fontSize: 10,
      padding: '1px 5px',
      borderRadius: 4,
      background: 'var(--dock-grey-100)',
      color: 'var(--dock-text-tertiary)',
      border: '1px solid var(--dock-border-primary)',
      fontWeight: 500
    }
  }, children);
}
Object.assign(window, {
  Button,
  IconButton,
  Pill,
  Tag,
  BadgeTag,
  Input,
  Avatar,
  Spinner,
  Kbd,
  TAG_COLORS
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/blinkit-ops-console/Primitives.jsx", error: String((e && e.message) || e) }); }

// ui_kits/blinkit-ops-console/Sidebar.jsx
try { (() => {
/* global React, IconButton */
const {
  useState
} = React;
function Sidebar({
  items,
  selectedId,
  onSelect,
  expanded,
  onToggle
}) {
  const [navHovered, setNavHovered] = useState(false);
  const isCollapsed = !expanded;
  // In collapsed state, hovering the navbar hides the logo and reveals the expand button.
  // The navbar width does NOT change on hover — it remains 52px.

  return /*#__PURE__*/React.createElement("aside", {
    onMouseEnter: () => isCollapsed && setNavHovered(true),
    onMouseLeave: () => isCollapsed && setNavHovered(false),
    style: {
      width: expanded ? 256 : 52,
      flexShrink: 0,
      background: 'var(--dock-surface-primary)',
      borderRight: '1px solid var(--dock-border-secondary)',
      display: 'flex',
      flexDirection: 'column',
      transition: 'width .3s ease-in-out',
      overflow: 'hidden'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '8px 4px 8px 8px',
      borderBottom: '1px solid var(--dock-border-secondary)',
      minHeight: 52
    }
  }, /*#__PURE__*/React.createElement("div", {
    onClick: isCollapsed ? onToggle : undefined,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      flex: 1,
      minWidth: 0,
      overflow: 'hidden',
      transition: 'opacity .3s ease-in-out',
      opacity: isCollapsed && navHovered ? 0 : 1,
      pointerEvents: isCollapsed && navHovered ? 'none' : 'auto',
      cursor: isCollapsed ? 'pointer' : 'default',
      zIndex: 1
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 36,
      height: 36,
      borderRadius: 8,
      flexShrink: 0,
      background: 'var(--dock-blinkit-yellow)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      color: 'var(--dock-blinkit-black)',
      fontWeight: 700,
      fontSize: 18,
      letterSpacing: '-.02em'
    }
  }, "B"), expanded && /*#__PURE__*/React.createElement("div", {
    style: {
      minWidth: 0,
      overflow: 'hidden',
      whiteSpace: 'nowrap'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 14,
      fontWeight: 600,
      lineHeight: '18px'
    }
  }, "Blinkit Admin"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 11,
      color: 'var(--dock-text-tertiary)',
      lineHeight: '14px'
    }
  }, "Ops Console"))), /*#__PURE__*/React.createElement("div", {
    style: {
      position: isCollapsed ? 'absolute' : 'static',
      left: isCollapsed ? 4 : undefined,
      top: isCollapsed ? '50%' : undefined,
      transform: isCollapsed ? 'translateY(-50%)' : undefined,
      opacity: isCollapsed ? navHovered ? 1 : 0 : 1,
      pointerEvents: isCollapsed && !navHovered ? 'none' : 'auto',
      transition: 'opacity .15s ease-in-out',
      zIndex: 2
    }
  }, /*#__PURE__*/React.createElement(IconButton, {
    icon: expanded ? 'keyboard-double-arrow-left' : 'keyboard-double-arrow-right',
    size: "sm",
    onClick: onToggle,
    title: expanded ? 'Collapse navigation' : 'Expand navigation'
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflowY: 'auto',
      padding: '8px 6px',
      display: 'flex',
      flexDirection: 'column',
      gap: 16
    }
  }, items.map((section, si) => /*#__PURE__*/React.createElement("div", {
    key: si
  }, expanded && section.title && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 10,
      fontWeight: 500,
      textTransform: 'uppercase',
      letterSpacing: '0.06em',
      color: 'var(--dock-text-tertiary)',
      padding: '4px 8px 6px'
    }
  }, section.title), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, section.items.map(item => /*#__PURE__*/React.createElement(NavItem, {
    key: item.id,
    item: item,
    selected: item.id === selectedId,
    onClick: () => onSelect(item.id),
    expanded: expanded
  })))))), /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--dock-border-secondary)',
      padding: 6
    }
  }, /*#__PURE__*/React.createElement(NavItem, {
    expanded: expanded,
    item: {
      id: '_help',
      label: 'Help & support',
      icon: 'help'
    },
    onClick: () => {}
  })));
}
function NavItem({
  item,
  selected,
  onClick,
  expanded
}) {
  const [hover, setHover] = useState(false);
  // Source: selected = alpha-dark-normal bg; hover-not-selected = alpha-dark-subtle bg
  const bg = selected ? 'var(--dock-alpha-dark-10)' // = surface-accent-alpha-dark-normal in light theme
  : hover ? 'var(--dock-alpha-dark-5)' : 'transparent';
  const fg = selected || hover ? 'var(--dock-text-primary)' : 'var(--dock-text-tertiary)';
  return /*#__PURE__*/React.createElement("button", {
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    title: !expanded ? item.label : undefined,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      padding: 8,
      borderRadius: 8,
      border: 0,
      background: bg,
      color: fg,
      fontFamily: 'Lexend',
      fontSize: 14,
      lineHeight: '18px',
      fontWeight: selected ? 500 : 400,
      cursor: 'pointer',
      width: '100%',
      transition: 'background .15s, color .15s',
      minHeight: 36,
      justifyContent: expanded ? 'flex-start' : 'center'
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: `--dock-icon-${item.icon}`,
    style: {
      fontSize: 20,
      flexShrink: 0
    }
  }), expanded && /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      textAlign: 'left',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, item.label), item.count != null && /*#__PURE__*/React.createElement("span", {
    style: {
      minWidth: 16,
      height: 16,
      padding: '0 5px',
      borderRadius: 9999,
      background: 'var(--dock-grey-dark-950)',
      color: 'var(--dock-text-only-white)',
      fontSize: 10,
      fontWeight: 500,
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, item.count), item.badge === 'new' && /*#__PURE__*/React.createElement("span", {
    style: {
      padding: '2px 6px',
      borderRadius: 9999,
      fontSize: 9,
      fontWeight: 600,
      letterSpacing: '0.04em',
      background: 'var(--dock-blue-600)',
      color: 'var(--dock-text-only-white)'
    }
  }, "NEW")));
}
Object.assign(window, {
  Sidebar
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/blinkit-ops-console/Sidebar.jsx", error: String((e && e.message) || e) }); }

// ui_kits/blinkit-ops-console/Toast.jsx
try { (() => {
/* global React */
const {
  useState,
  useEffect,
  useCallback
} = React;
let pushFn = null;
function pushToast(t) {
  if (pushFn) pushFn(t);
}
function ToastContainer() {
  const [toasts, setToasts] = useState([]);
  useEffect(() => {
    pushFn = t => {
      const id = Math.random().toString(36).slice(2);
      setToasts(arr => [...arr, {
        ...t,
        id
      }]);
      setTimeout(() => setToasts(arr => arr.filter(x => x.id !== id)), t.duration || 4000);
    };
  }, []);
  const dismiss = useCallback(id => setToasts(arr => arr.filter(t => t.id !== id)), []);
  const variants = {
    success: {
      bg: 'var(--dock-green-100)',
      fg: 'var(--dock-green-700)',
      icon: 'check-circle'
    },
    error: {
      bg: 'var(--dock-red-100)',
      fg: 'var(--dock-red-700)',
      icon: 'error'
    },
    warning: {
      bg: 'var(--dock-orange-100)',
      fg: 'var(--dock-orange-700)',
      icon: 'warning'
    },
    info: {
      bg: 'var(--dock-blue-100)',
      fg: 'var(--dock-blue-700)',
      icon: 'info'
    }
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      right: 16,
      bottom: 16,
      zIndex: 400,
      display: 'flex',
      flexDirection: 'column',
      gap: 8,
      alignItems: 'flex-end'
    }
  }, toasts.map(t => {
    const v = variants[t.type || 'info'];
    return /*#__PURE__*/React.createElement("div", {
      key: t.id,
      style: {
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        minWidth: 320,
        maxWidth: 420,
        background: 'var(--dock-surface-primary)',
        border: '1px solid var(--dock-border-secondary)',
        borderRadius: 8,
        padding: '12px 14px',
        boxShadow: 'var(--dock-shadow-lg)',
        animation: 'dockToastIn .2s ease-out'
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        width: 32,
        height: 32,
        borderRadius: 8,
        background: v.bg,
        color: v.fg,
        flexShrink: 0,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center'
      }
    }, /*#__PURE__*/React.createElement("i", {
      className: `--dock-icon-${v.icon}`,
      style: {
        fontSize: 18
      }
    })), /*#__PURE__*/React.createElement("div", {
      style: {
        flex: 1,
        minWidth: 0
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        fontFamily: 'Lexend',
        fontSize: 14,
        fontWeight: 600,
        lineHeight: '18px'
      }
    }, t.title), t.desc && /*#__PURE__*/React.createElement("div", {
      style: {
        fontFamily: 'Lexend',
        fontSize: 13,
        color: 'var(--dock-text-tertiary)',
        marginTop: 2
      }
    }, t.desc)), /*#__PURE__*/React.createElement("button", {
      onClick: () => dismiss(t.id),
      style: {
        background: 'transparent',
        border: 0,
        color: 'var(--dock-text-tertiary)',
        cursor: 'pointer',
        display: 'flex',
        alignItems: 'center',
        padding: 4
      }
    }, /*#__PURE__*/React.createElement("i", {
      className: "--dock-icon-close"
    })));
  }));
}
Object.assign(window, {
  ToastContainer,
  pushToast
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/blinkit-ops-console/Toast.jsx", error: String((e && e.message) || e) }); }

})();
