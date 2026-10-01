import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BriskersLanguageController extends ChangeNotifier {
  BriskersLanguageController._();

  static final BriskersLanguageController instance =
      BriskersLanguageController._();

  static const _preferenceKey = 'briskers_language_code';

  String _code = 'en';

  String get code => _code;
  bool get isSpanish => _code == 'es';
  Locale get locale => Locale(_code);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_preferenceKey);
    if (saved == 'es' || saved == 'en') {
      _code = saved!;
    }
  }

  Future<void> setLanguage(String code) async {
    final normalized = code == 'es' ? 'es' : 'en';
    if (_code == normalized) return;
    _code = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, _code);
    notifyListeners();
  }

  String t(String key) {
    final language = _translations[_code] ?? _translations['en']!;
    return language[key] ?? _translations['en']![key] ?? key;
  }
}

String tr(String key) => BriskersLanguageController.instance.t(key);

String roleLabel(String roleCode) {
  switch (roleCode) {
    case 'owner':
      return tr('owner');
    case 'manager':
      return tr('foreman');
    case 'office':
      return tr('secretary');
    case 'mechanic':
      return tr('mechanic');
    case 'porter':
      return tr('porter');
    case 'kiosk':
      return tr('checkIn');
    case 'customer':
      return tr('customer');
    default:
      return roleCode.toUpperCase();
  }
}

String jobStatusLabel(String? code, String fallback) {
  switch (code) {
    case 'in_progress':
      return tr('inProgress');
    case 'pending_approval':
      return tr('pendingApproval');
    case 'waiting_parts':
      return tr('waitingParts');
    case 'needs_recheck':
      return tr('needsRecheck');
    case 'under_review':
      return tr('underReview');
    case 'completed':
      return tr('completed');
    default:
      return fallback;
  }
}

const Map<String, Map<String, String>> _translations = {
  'en': {
    'dashboard': 'Dashboard',
    'customers': 'Customers',
    'customer': 'Customer',
    'appointments': 'Appointments',
    'jobs': 'Jobs',
    'more': 'More',
    'schedule': 'Schedule',
    'owner': 'OWNER',
    'foreman': 'FOREMAN',
    'secretary': 'SECRETARY',
    'mechanic': 'MECHANIC',
    'porter': 'PORTER',
    'checkIn': 'CHECK-IN',
    'estimates': 'Estimates',
    'invoices': 'Invoices',
    'expenses': 'Expenses',
    'activeJobs': 'Active Jobs',
    'today': 'Today',
    'settings': 'Settings',
    'language': 'Language',
    'languageSubtitle': 'Choose the language used by the Briskers app',
    'english': 'English',
    'spanish': 'Español',
    'languageTest': 'Language testing',
    'languageTestBody':
        'This changes the Briskers interface. Receipt and vendor text stays exactly as printed.',
    'shopInformation': 'Shop information',
    'shopInformationSub': 'Name, address, hours, phone, links and customer page',
    'kioskCheckIn': 'Kiosk Check-In',
    'kioskCheckInSub': 'Customer disclaimer and public check-in settings',
    'startKioskMode': 'Start Kiosk Mode (Test)',
    'startKioskModeSub':
        'Open customer check-in on this device without signing out',
    'employees': 'Employees',
    'employeesSub': 'Personal information, positions and pay settings',
    'jobStatuses': 'Job statuses',
    'jobStatusesSub': 'Names, colors, icons and custom workflow statuses',
    'invoiceStatuses': 'Invoice statuses',
    'invoiceStatusesSub': 'Names, colors, icons and display order',
    'itemsCatalog': 'Items / Catalog',
    'itemsCatalogSub': 'Parts, labor, services, prices, taxability and categories',
    'itemCategories': 'Item Categories',
    'itemCategoriesSub': 'Edit the category list used by catalog items',
    'taxesInvoicing': 'Taxes & Invoicing',
    'taxesInvoicingSub': 'Default sales tax rate and invoice tax behavior',
    'transactionsSetup': 'Transactions setup',
    'transactionsSetupSub':
        'Accounts, categories, payees, quick and recurring transactions',
    'paymentMethods': 'Payment Methods',
    'paymentMethodsSub': 'Cash, cards, Zelle and other accepted methods',
    'notifications': 'Notifications',
    'notificationsSub':
        'Customer and employee notification options — coming next',
    'expensesIncome': 'Expenses & income',
    'expensesIncomeSub': 'Expenses, receipts and job costs',
    'reportsProfitability': 'Reports & profitability',
    'reportsProfitabilitySub': 'Owner only — coming in the next build',
    'appOptions': 'Shop information and app options',
    'signOut': 'Sign out',
    'createNewEstimate': 'Create new estimate',
    'viewEstimates': 'View estimates',
    'createNewInvoice': 'Create new invoice',
    'viewInvoices': 'View invoices',
    'newAppointment': 'New appointment',
    'viewAppointments': 'View appointments',
    'addGeneralExpense': 'Add general expense',
    'quickGeneralExpense': 'Quick general expense',
    'viewTransactions': 'View transactions',
    'recurringTransactions': 'Recurring transactions',
    'all': 'All',
    'upcoming': 'Upcoming',
    'past': 'Past',
    'total': 'Total',
    'add': 'Add',
    'confirmed': 'Confirmed',
    'tentative': 'Tentative',
    'noShow': 'No show',
    'canceled': 'Canceled',
    'checkedIn': 'Checked in',
    'finished': 'Finished',
    'changeStatus': 'Change status',
    'inProgress': 'In Progress',
    'pendingApproval': 'Pending approval',
    'waitingParts': 'Waiting parts',
    'needsRecheck': 'Needs Recheck',
    'underReview': 'Under review',
    'completed': 'Completed',
    'transactionDate': 'Transaction date',
    'descriptionNotes': 'Description / notes',
    'amount': 'Amount',
    'payee': 'Payee',
    'payer': 'Payer',
    'category': 'Category',
    'paidFrom': 'Paid from',
    'depositedTo': 'Deposited to',
    'scanAddReceipt': 'Scan / add receipt',
    'readingReceipt': 'Reading receipt...',
    'receiptReadReview': 'Receipt read — review the fields before saving.',
    'pendingCustomerRequests': 'Pending customer requests',
    'savedAppointmentsOffline':
        'Showing saved appointments • check-in can be queued offline',
    'noAppointments': 'No appointments in this view.',
    'searchCustomers': 'Search customers',
    'savedCustomersOffline':
        'Showing saved customers • editing requires a connection',
    'cars': 'cars',
    'editTransaction': 'Edit transaction',
    'copyTransaction': 'Copy transaction',
    'addIncome': 'Add income',
    'addExpense': 'Add expense',
    'quickTransaction': 'Quick transaction',
    'linkedAutomatically': 'Linked automatically',
    'findPayer': 'Find payer',
    'findPayee': 'Find payee',
    'searchByName': 'Search by name',
    'newPayee': 'New payee',
    'selectCategory': 'Select a category',
    'selectPayer': 'Select a payer',
    'selectPayee': 'Select a payee',
    'selectDepositAccount': 'Select deposit account',
    'selectPaymentAccount': 'Select payment account',
    'repeatTransaction': 'Repeat transaction',
    'saveTransaction': 'Save transaction',
    'saving': 'Saving...',
    'scheduledEvent': 'Scheduled event',
  },
  'es': {
    'dashboard': 'Panel',
    'customers': 'Clientes',
    'customer': 'Cliente',
    'appointments': 'Citas',
    'jobs': 'Trabajos',
    'more': 'Más',
    'schedule': 'Agenda',
    'owner': 'PROPIETARIO',
    'foreman': 'JEFE DE TALLER',
    'secretary': 'SECRETARÍA',
    'mechanic': 'MECÁNICO',
    'porter': 'AYUDANTE',
    'checkIn': 'REGISTRO',
    'estimates': 'Presupuestos',
    'invoices': 'Facturas',
    'expenses': 'Gastos',
    'activeJobs': 'Trabajos activos',
    'today': 'Hoy',
    'settings': 'Configuración',
    'language': 'Idioma',
    'languageSubtitle': 'Elige el idioma de la aplicación Briskers',
    'english': 'English',
    'spanish': 'Español',
    'languageTest': 'Prueba de idioma',
    'languageTestBody':
        'Esto cambia la interfaz de Briskers. El texto de recibos y proveedores se mantiene exactamente como aparece impreso.',
    'shopInformation': 'Información del taller',
    'shopInformationSub':
        'Nombre, dirección, horario, teléfono, enlaces y página del cliente',
    'kioskCheckIn': 'Registro en kiosco',
    'kioskCheckInSub':
        'Aviso al cliente y configuración del registro público',
    'startKioskMode': 'Iniciar modo kiosco (prueba)',
    'startKioskModeSub':
        'Abrir el registro del cliente en este dispositivo sin cerrar sesión',
    'employees': 'Empleados',
    'employeesSub': 'Información personal, puestos y configuración de pago',
    'jobStatuses': 'Estados de trabajo',
    'jobStatusesSub':
        'Nombres, colores, iconos y estados personalizados del flujo',
    'invoiceStatuses': 'Estados de factura',
    'invoiceStatusesSub': 'Nombres, colores, iconos y orden de visualización',
    'itemsCatalog': 'Artículos / Catálogo',
    'itemsCatalogSub':
        'Piezas, mano de obra, servicios, precios, impuestos y categorías',
    'itemCategories': 'Categorías de artículos',
    'itemCategoriesSub': 'Editar las categorías usadas por los artículos',
    'taxesInvoicing': 'Impuestos y facturación',
    'taxesInvoicingSub':
        'Tasa de impuesto predeterminada y comportamiento de facturas',
    'transactionsSetup': 'Configuración de transacciones',
    'transactionsSetupSub':
        'Cuentas, categorías, proveedores, transacciones rápidas y recurrentes',
    'paymentMethods': 'Métodos de pago',
    'paymentMethodsSub': 'Efectivo, tarjetas, Zelle y otros métodos aceptados',
    'notifications': 'Notificaciones',
    'notificationsSub':
        'Opciones de notificación para clientes y empleados — próximamente',
    'expensesIncome': 'Gastos e ingresos',
    'expensesIncomeSub': 'Gastos, recibos y costos de trabajos',
    'reportsProfitability': 'Reportes y rentabilidad',
    'reportsProfitabilitySub':
        'Solo propietario — disponible en una próxima versión',
    'appOptions': 'Información del taller y opciones de la aplicación',
    'signOut': 'Cerrar sesión',
    'createNewEstimate': 'Crear nuevo presupuesto',
    'viewEstimates': 'Ver presupuestos',
    'createNewInvoice': 'Crear nueva factura',
    'viewInvoices': 'Ver facturas',
    'newAppointment': 'Nueva cita',
    'viewAppointments': 'Ver citas',
    'addGeneralExpense': 'Agregar gasto general',
    'quickGeneralExpense': 'Gasto general rápido',
    'viewTransactions': 'Ver transacciones',
    'recurringTransactions': 'Transacciones recurrentes',
    'all': 'Todos',
    'upcoming': 'Próximas',
    'past': 'Anteriores',
    'total': 'Total',
    'add': 'Agregar',
    'confirmed': 'Confirmada',
    'tentative': 'Tentativa',
    'noShow': 'No se presentó',
    'canceled': 'Cancelada',
    'checkedIn': 'Registrada',
    'finished': 'Finalizada',
    'changeStatus': 'Cambiar estado',
    'inProgress': 'En progreso',
    'pendingApproval': 'Pendiente de aprobación',
    'waitingParts': 'Esperando piezas',
    'needsRecheck': 'Necesita revisión',
    'underReview': 'En revisión',
    'completed': 'Completado',
    'transactionDate': 'Fecha de transacción',
    'descriptionNotes': 'Descripción / notas',
    'amount': 'Monto',
    'payee': 'Proveedor',
    'payer': 'Pagador',
    'category': 'Categoría',
    'paidFrom': 'Pagado desde',
    'depositedTo': 'Depositado en',
    'scanAddReceipt': 'Escanear / agregar recibo',
    'readingReceipt': 'Leyendo recibo...',
    'receiptReadReview':
        'Recibo leído — revisa los campos antes de guardar.',
    'pendingCustomerRequests': 'Solicitudes pendientes de clientes',
    'savedAppointmentsOffline':
        'Mostrando citas guardadas • el registro puede quedar en cola sin conexión',
    'noAppointments': 'No hay citas en esta vista.',
    'searchCustomers': 'Buscar clientes',
    'savedCustomersOffline':
        'Mostrando clientes guardados • editar requiere conexión',
    'cars': 'vehículos',
    'editTransaction': 'Editar transacción',
    'copyTransaction': 'Copiar transacción',
    'addIncome': 'Agregar ingreso',
    'addExpense': 'Agregar gasto',
    'quickTransaction': 'Transacción rápida',
    'linkedAutomatically': 'Vinculado automáticamente',
    'findPayer': 'Buscar pagador',
    'findPayee': 'Buscar proveedor',
    'searchByName': 'Buscar por nombre',
    'newPayee': 'Nuevo proveedor',
    'selectCategory': 'Selecciona una categoría',
    'selectPayer': 'Selecciona un pagador',
    'selectPayee': 'Selecciona un proveedor',
    'selectDepositAccount': 'Selecciona la cuenta de depósito',
    'selectPaymentAccount': 'Selecciona la cuenta de pago',
    'repeatTransaction': 'Repetir transacción',
    'saveTransaction': 'Guardar transacción',
    'saving': 'Guardando...',
    'scheduledEvent': 'Evento programado',
  },
};
