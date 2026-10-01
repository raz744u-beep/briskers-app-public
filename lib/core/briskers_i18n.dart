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
    'invoiceOpen': 'Open',
    'invoicePendingClose': 'Pending Close',
    'invoicePaid': 'Paid',
    'invoicePartial': 'Partial',
    'documentDraft': 'Draft',
    'documentIssued': 'Issued',
    'documentAccepted': 'Accepted',
    'documentDeclined': 'Declined',
    'documentExpired': 'Expired',
    'documentVoid': 'Void',
    'jobLabel': 'Job',
    'viewExpenses': 'View expenses',
    'noRelatedExpenses': 'No related expenses',
    'invoiceLinked': 'Invoice-linked',
    'jobExpense': 'Job expense',
    'invoice': 'Invoice',
    'estimate': 'Estimate',
    'date': 'Date',
    'itemsTab': 'Items',
    'paymentTab': 'Payment',
    'notesTab': 'Notes',
    'itemColumn': 'Item',
    'qtyColumn': 'Qty',
    'amountColumn': 'Amount',
    'subtotal': 'Subtotal',
    'tax': 'Tax',
    'addItem': 'Add Item',
    'preview': 'Preview',
    'send': 'Send',
    'editInvoice': 'Edit invoice',
    'editEstimate': 'Edit estimate',
    'copyInvoice': 'Copy invoice',
    'vehicleFindings': 'Vehicle findings',
    'deleteInvoice': 'Delete invoice',
    'deleteEstimate': 'Delete estimate',
    'createInvoice': 'Create invoice',
    'invoiceNotes': 'Invoice Notes',
    'estimateNotes': 'Estimate Notes',
    'edit': 'Edit',
    'noInvoiceNotes': 'No invoice notes yet.',
    'noEstimateNotes': 'No estimate notes yet.',
    'notesPdfHelp': 'These notes appear on the PDF preview.',
    'saveNotes': 'Save notes',
    'enterDocumentNotes': 'Enter notes that should appear on the document.',
    'searchItems': 'Search items',
    'noMatchingItems': 'No matching items.',
    'addFromItemList': 'Add from item list',
    'addCustomLine': 'Add custom line',
    'addDiscount': 'Add discount',
    'item': 'Item',
    'description': 'Description',
    'quantity': 'Quantity',
    'price': 'Price',
    'type': 'Type',
    'partItem': 'Part / Item',
    'labor': 'Labor',
    'shopSupply': 'Shop supply',
    'other': 'Other',
    'shipping': 'Shipping',
    'saveChanges': 'Save Changes',
    'addToInvoice': 'Add to Invoice',
    'addToEstimate': 'Add to Estimate',
    'translateEnglishNotice':
        'Text you type in Spanish is translated to English when saved.',
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
    'addCustomer': 'Add customer',
    'filterJobs': 'Filter jobs',
    'localDatabaseSync': 'Local database & sync',
    'localDatabaseSyncSub':
        'Cached data, offline queue, sync status and testing',
    'localDatabaseActive': 'Local database active',
    'schemaVersion': 'schema',
    'cachedOnDevice': 'Cached on this device',
    'vehicles': 'Vehicles',
    'preInspections': 'Pre-inspections',
    'offlineQueue': 'Offline queue',
    'pendingUpload': 'Pending upload / sync',
    'syncConflicts': 'Sync conflicts',
    'syncHistory': 'Sync history',
    'lastPull': 'Last download',
    'lastPush': 'Last upload',
    'never': 'Never',
    'notSyncedYet': 'No sync history yet.',
    'syncNow': 'Sync now',
    'syncing': 'Syncing...',
    'syncCompleted': 'Sync completed.',
    'syncPartial': 'Sync finished with one or more errors.',
    'refresh': 'Refresh',
    'offlineTest': 'Offline test',
    'offlineTestReady':
        'Customers, jobs and appointments are cached. This device is ready for an airplane-mode test.',
    'offlineTestNeedsCache':
        'Open the app online and let it sync before testing offline.',
    'offlineStep1': 'Turn on Airplane Mode and turn Wi-Fi off.',
    'offlineStep2': 'Force-close Briskers and reopen it.',
    'offlineStep3':
        'Open Customers, Appointments and Jobs and confirm saved data appears.',
    'offlineStep4':
        'Make an offline-capable change, reopen the app, then reconnect and use Sync now.',
    'customersVehicles': 'Customers & vehicles',
    'workPerformed': 'Work performed',
    'vehicleFindings': 'Vehicle findings',
    'findingPhotos': 'Finding photos',
    'preInspection': 'Pre-inspection',
    'inspectionPhotos': 'Inspection photos',
    'appointmentCheckIn': 'Appointment check-in',
    'kioskWalkIn': 'Kiosk walk-in',
    'aiReceiptSamples': 'AI receipt samples',
    'aiReceiptSamplesSub':
        'Upload real vendor receipts or invoices as layout references for AI extraction',
    'trainingReferenceOnly': 'Training / reference only',
    'trainingReferenceExplanation':
        'These real receipts and invoices teach Briskers where a vendor usually prints invoice numbers, totals, surcharges, part numbers and line items.',
    'noAccountingEffect': 'No accounting effect',
    'noAccountingEffectExplanation':
        'Training samples never create expenses, transactions, inventory, invoices or customer records.',
    'addSample': 'Add sample',
    'choosePayee': 'Choose payee',
    'chooseSampleImages': 'Choose sample images',
    'chooseMultipleSamples': 'You can select more than one image',
    'takeSamplePhoto': 'Take sample photo',
    'defaultSurcharge': 'default surcharge',
    'trainingSampleAdded': 'Training sample added.',
    'trainingSamplesAdded': 'training samples added.',
    'removeTrainingSample': 'Remove training sample?',
    'removeTrainingSampleQuestion':
        'This removes the reference image from AI training for this vendor.',
    'remove': 'Remove',
    'cancel': 'Cancel',
    'samples': 'samples',
    'receiptSample': 'Receipt sample',
    'usedAsLayoutReference': 'Used only as an AI layout reference',
    'noTrainingSamples':
        'No AI receipt samples yet. Add a vendor receipt or invoice to teach Briskers that layout.',
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
    'invoiceOpen': 'Abierta',
    'invoicePendingClose': 'Pendiente de cierre',
    'invoicePaid': 'Pagada',
    'invoicePartial': 'Parcial',
    'documentDraft': 'Borrador',
    'documentIssued': 'Emitida',
    'documentAccepted': 'Aceptada',
    'documentDeclined': 'Rechazada',
    'documentExpired': 'Vencida',
    'documentVoid': 'Anulada',
    'jobLabel': 'Trabajo',
    'viewExpenses': 'Ver gastos',
    'noRelatedExpenses': 'No hay gastos relacionados',
    'invoiceLinked': 'Vinculado a la factura',
    'jobExpense': 'Gasto del trabajo',
    'invoice': 'Factura',
    'estimate': 'Presupuesto',
    'date': 'Fecha',
    'itemsTab': 'Artículos',
    'paymentTab': 'Pago',
    'notesTab': 'Notas',
    'itemColumn': 'Artículo',
    'qtyColumn': 'Cant.',
    'amountColumn': 'Monto',
    'subtotal': 'Subtotal',
    'tax': 'Impuesto',
    'addItem': 'Agregar',
    'preview': 'Vista previa',
    'send': 'Enviar',
    'editInvoice': 'Editar factura',
    'editEstimate': 'Editar presupuesto',
    'copyInvoice': 'Copiar factura',
    'vehicleFindings': 'Hallazgos del vehículo',
    'deleteInvoice': 'Eliminar factura',
    'deleteEstimate': 'Eliminar presupuesto',
    'createInvoice': 'Crear factura',
    'invoiceNotes': 'Notas de la factura',
    'estimateNotes': 'Notas del presupuesto',
    'edit': 'Editar',
    'noInvoiceNotes': 'Todavía no hay notas de la factura.',
    'noEstimateNotes': 'Todavía no hay notas del presupuesto.',
    'notesPdfHelp': 'Estas notas aparecen en la vista previa del PDF.',
    'saveNotes': 'Guardar notas',
    'enterDocumentNotes': 'Escribe las notas que deben aparecer en el documento.',
    'searchItems': 'Buscar artículos',
    'noMatchingItems': 'No hay artículos que coincidan.',
    'addFromItemList': 'Agregar de la lista de artículos',
    'addCustomLine': 'Agregar línea personalizada',
    'addDiscount': 'Agregar descuento',
    'item': 'Artículo',
    'description': 'Descripción',
    'quantity': 'Cantidad',
    'price': 'Precio',
    'type': 'Tipo',
    'partItem': 'Pieza / artículo',
    'labor': 'Mano de obra',
    'shopSupply': 'Suministro del taller',
    'other': 'Otro',
    'shipping': 'Envío',
    'saveChanges': 'Guardar cambios',
    'addToInvoice': 'Agregar a la factura',
    'addToEstimate': 'Agregar al presupuesto',
    'translateEnglishNotice':
        'El texto que escribas en español se traducirá al inglés al guardarlo.',
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
    'addCustomer': 'Agregar cliente',
    'filterJobs': 'Filtrar trabajos',
    'localDatabaseSync': 'Base de datos local y sincronización',
    'localDatabaseSyncSub':
        'Datos guardados, cola sin conexión, estado y pruebas',
    'localDatabaseActive': 'Base de datos local activa',
    'schemaVersion': 'esquema',
    'cachedOnDevice': 'Guardado en este dispositivo',
    'vehicles': 'Vehículos',
    'preInspections': 'Preinspecciones',
    'offlineQueue': 'Cola sin conexión',
    'pendingUpload': 'Pendiente de subir / sincronizar',
    'syncConflicts': 'Conflictos de sincronización',
    'syncHistory': 'Historial de sincronización',
    'lastPull': 'Última descarga',
    'lastPush': 'Última subida',
    'never': 'Nunca',
    'notSyncedYet': 'Todavía no hay historial de sincronización.',
    'syncNow': 'Sincronizar ahora',
    'syncing': 'Sincronizando...',
    'syncCompleted': 'Sincronización completada.',
    'syncPartial': 'La sincronización terminó con uno o más errores.',
    'refresh': 'Actualizar',
    'offlineTest': 'Prueba sin conexión',
    'offlineTestReady':
        'Clientes, trabajos y citas están guardados. Este dispositivo está listo para una prueba en modo avión.',
    'offlineTestNeedsCache':
        'Abre la aplicación con internet y deja que sincronice antes de probar sin conexión.',
    'offlineStep1': 'Activa el modo avión y apaga Wi-Fi.',
    'offlineStep2': 'Cierra Briskers completamente y vuelve a abrirlo.',
    'offlineStep3':
        'Abre Clientes, Citas y Trabajos y confirma que aparecen los datos guardados.',
    'offlineStep4':
        'Haz un cambio permitido sin conexión, reabre la aplicación, vuelve a conectarte y usa Sincronizar ahora.',
    'customersVehicles': 'Clientes y vehículos',
    'workPerformed': 'Trabajo realizado',
    'vehicleFindings': 'Hallazgos del vehículo',
    'findingPhotos': 'Fotos de hallazgos',
    'preInspection': 'Preinspección',
    'inspectionPhotos': 'Fotos de inspección',
    'appointmentCheckIn': 'Registro de cita',
    'kioskWalkIn': 'Registro sin cita en kiosco',
    'aiReceiptSamples': 'Muestras de recibos para IA',
    'aiReceiptSamplesSub':
        'Sube recibos o facturas reales de proveedores como referencia de diseño para la extracción con IA',
    'trainingReferenceOnly': 'Solo entrenamiento / referencia',
    'trainingReferenceExplanation':
        'Estos recibos y facturas reales enseñan a Briskers dónde suele imprimir cada proveedor el número de factura, totales, recargos, números de pieza y artículos.',
    'noAccountingEffect': 'Sin efecto contable',
    'noAccountingEffectExplanation':
        'Las muestras de entrenamiento nunca crean gastos, transacciones, inventario, facturas ni registros de clientes.',
    'addSample': 'Agregar muestra',
    'choosePayee': 'Elegir proveedor',
    'chooseSampleImages': 'Elegir imágenes de muestra',
    'chooseMultipleSamples': 'Puedes seleccionar más de una imagen',
    'takeSamplePhoto': 'Tomar foto de muestra',
    'defaultSurcharge': 'recargo predeterminado',
    'trainingSampleAdded': 'Muestra de entrenamiento agregada.',
    'trainingSamplesAdded': 'muestras de entrenamiento agregadas.',
    'removeTrainingSample': '¿Eliminar muestra de entrenamiento?',
    'removeTrainingSampleQuestion':
        'Esto elimina la imagen de referencia del entrenamiento de IA para este proveedor.',
    'remove': 'Eliminar',
    'cancel': 'Cancelar',
    'samples': 'muestras',
    'receiptSample': 'Muestra de recibo',
    'usedAsLayoutReference': 'Usada solo como referencia de diseño para la IA',
    'noTrainingSamples':
        'Todavía no hay muestras para IA. Agrega un recibo o factura de proveedor para enseñar ese formato a Briskers.',
  },
};
