<?php

namespace App\Controller\Api;

use Doctrine\Persistence\ManagerRegistry;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;
use Symfony\Component\DependencyInjection\ParameterBag\ParameterBagInterface;
use Symfony\Bridge\Twig\Mime\TemplatedEmail;
use Symfony\Component\Mailer\MailerInterface;
use Symfony\Component\Mailer\Exception\TransportExceptionInterface;
use App\Service\WebPathService;
use App\Entity\User;
use App\Service\ReportPriorityService;
use App\Entity\Report;
use App\Entity\ReportType;
use App\Service\MediaService;
use App\Service\ReportNotifier;

#[Route('/api')]
class ApiController extends AbstractController
{
    /** Stati che l'app puo' impostare: bozza oppure segnalazione inviata. */
    private const USER_STATUSES = ['in_creazione', 'pending'];

    /** Stati in cui l'utente puo' ancora modificare/eliminare la segnalazione. */
    private const EDITABLE_STATUSES = ['in_creazione', 'pending'];

    /** Thumbnail generata per ogni immagine caricata (gallery app + admin). */
    private const THUMB_PREFIX = 'thumb_';
    private const THUMB_SIZE = 300;
    private const THUMB_QUALITY = 82;
    private const THUMB_EXTENSIONS = ['jpg', 'jpeg', 'png', 'webp'];

    /** Le immagini oltre 1 MB vengono ricompresse prima di essere archiviate. */
    private const COMPRESS_THRESHOLD_BYTES = 1048576;
    private const COMPRESS_MAX_SIZE = 1600;
    private const COMPRESS_QUALITY = 80;

    /**
     * Rettangolo che contiene il confine di Corbetta (con un piccolo
     * margine): serve come viewbox per Nominatim. Il controllo vero e'
     * il poligono in config/corbetta_boundary.json.
     */
    private const CORBETTA_BOUNDS = [
        'minLat' => 45.4300,
        'maxLat' => 45.4880,
        'minLon' => 8.8975,
        'maxLon' => 8.9690,
    ];

    /** Confine di Corbetta (OSM relazione 45011), lista di [lat, lng]. */
    private const CORBETTA_BOUNDARY_FILE = '/config/corbetta_boundary.json';

    /** @var array<int, array{0: float, 1: float}>|null */
    private ?array $corbettaPolygon = null;

    protected $mr;
    protected $params;
    protected $webPath;
    protected $priority;

    public function __construct(ManagerRegistry $managerRegistry, ParameterBagInterface $params, ReportPriorityService $priority, WebPathService $webPath)
    {
        $this->mr = $managerRegistry;
        $this->params = $params;
        $this->webPath = $webPath;
        $this->priority = $priority;
    }

    private function getAuthenticatedUser(Request $request): ?User
    {
        $token = $request->headers->get('X-AUTH-TOKEN');
        if (!$token) {
            return null;
        }

        $em = $this->mr->getManager();
        $user = $em->getRepository(User::class)->findOneBy(['apiToken' => $token]);

        // Un account non piu' abilitato non deve poter usare un token gia' emesso
        if ($user !== null && !$this->canLogin($user)) {
            return null;
        }

        return $user;
    }

    /** Chi puo' usare l'app: staff attivo, non sospeso, con il permesso sulle segnalazioni. */
    private function canLogin(User $user): bool
    {
        return $user->getRole() === 'ROLE_STAFF'
            && $user->isIsActive()
            && $user->isIsAdminActive()
            && $user->getCanViewPermission('reports');
    }

    /**
     * Chi puo' creare, modificare o eliminare le proprie segnalazioni.
     *
     * L'app e' uno strumento da cittadino: chi ci entra segnala. Il permesso
     * 'reports' decide CHI entra (vedi canLogin), non cosa puo' fare una
     * volta dentro, quindi qui basta averlo. La distinzione r / rw resta
     * valida sul sito, dove separa chi consulta da chi scrive.
     *
     * Restano comunque le sole PROPRIE: a dirlo e' canEditReport, che
     * confronta l'autore.
     */
    private function canWrite(User $user): bool
    {
        return $user->getCanViewPermission('reports');
    }

    /** Chi gestisce le segnalazioni dall'area riservata (stato, accorpamenti). */
    private function canManage(User $user): bool
    {
        return $user->getCanViewPermission('reports_manage');
    }

    // Nell'app non esiste piu' un elenco completo: ognuno vede e gestisce
    // le proprie segnalazioni, chiunque sia. Vedere tutto e' un lavoro da
    // area riservata del sito, dove il permesso 'reports_manage' continua a
    // valere. Per questo qui non c'e' piu' un canSeeAllReports.

    /**
     * Chi puo' modificare o eliminare questa segnalazione dall'app: solo il
     * suo autore, solo finche' non e' stata presa in carico.
     *
     * Chi gestisce le segnalazioni vede anche quelle degli altri, ma da qui
     * non le tocca: sull'app si modifica solo cio' che si e' inserito.
     * Le altre si lavorano dall'area riservata.
     */
    private function canEditReport(User $user, Report $report): bool
    {
        return $this->canWrite($user)
            && $report->getUser()?->getId() === $user->getId()
            && in_array($report->getStatus(), self::EDITABLE_STATUSES, true);
    }

    /**
     * URL assoluto di un file pubblico ('uploads/reports/12/foto.jpg').
     * Passa da getBasePath() perche' in locale il sito sta in sottocartella:
     * un percorso tipo /uploads/... li' non esiste. L'app riceve sempre URL
     * completi e non deve piu' comporli da sola.
     */
    private function publicUrl(Request $request, string $relative): string
    {
        return $request->getSchemeAndHttpHost().$request->getBasePath().'/'.ltrim($relative, '/');
    }

    private function errorResponse(string $message, int $status = 400): JsonResponse
    {
        return new JsonResponse(['success' => false, 'message' => $message], $status);
    }

    // ==================== AUTH ====================

    #[Route('/login', name: 'api_login', methods: ['POST'])]
    public function login(Request $request, UserPasswordHasherInterface $passwordHasher): JsonResponse
    {
        $data = json_decode($request->getContent(), true);
        $email = $data['email'] ?? '';
        $password = $data['password'] ?? '';

        if (!$email || !$password) {
            return $this->errorResponse('Email e password sono obbligatori.');
        }

        $em = $this->mr->getManager();
        $user = $em->getRepository(User::class)->findOneBy(['email' => $email]);

        if (!$user) {
            return $this->errorResponse('Credenziali non valide.', 401);
        }

        if ($user->getRole() !== 'ROLE_STAFF') {
            return $this->errorResponse("L'account non e' abilitato all'accesso.", 403);
        }

        if (!$user->isIsActive() || !$user->isIsAdminActive()) {
            return $this->errorResponse('Account non attivo.', 403);
        }

        if (!$user->getCanViewPermission('reports')) {
            return $this->errorResponse("L'account non ha il permesso di usare l'app delle segnalazioni.", 403);
        }

        if (!$passwordHasher->isPasswordValid($user, $password)) {
            return $this->errorResponse('Credenziali non valide.', 401);
        }

        // Generate API token
        $token = bin2hex(random_bytes(32));
        $user->setApiToken($token);
        $em->flush();

        return new JsonResponse([
            'success' => true,
            'token' => $token,
            'user' => $this->serializeUser($user),
        ]);
    }

    /**
     * Blocco utente mandato all'app.
     *
     * Viaggia col login e con l'elenco delle segnalazioni: l'app lo rilegge
     * a ogni caricamento della lista, cosi' un permesso tolto o dato sul sito
     * ha effetto subito, senza rifare l'accesso.
     */
    private function serializeUser(User $user): array
    {
        return [
            'id' => $user->getId(),
            'email' => $user->getEmail(),
            'name' => $user->getName(),
            'surname' => $user->getSurname(),
            'role' => $user->getRole(),
            // L'app legge il permesso da qui ("" | "r" | "rw"): "segnalazioni"
            // e' la chiave storica, "reports" e' lo slug del permesso.
            //
            // Per l'app conta solo se c'e' o non c'e': chi ha il permesso
            // entra e segnala. La differenza fra "r" e "rw" resta valida sul
            // sito, dove separa chi consulta da chi scrive.
            //
            // Qui dentro va SOLO il permesso dell'app ('reports'). La
            // gestione ('reports_manage') sta fuori, in canManageReports:
            // l'app cerca il modulo per nome e "reports_manage" contiene
            // "reports", quindi dentro questa mappa rischierebbe di essere
            // letto come se fosse il permesso dell'app.
            'permissions' => [
                'segnalazioni' => $user->getPermissionType('reports'),
                'reports' => $user->getPermissionType('reports'),
            ],
            'canEditReports' => $user->getCanEditPermission('reports'),
            // Gestione in area riservata. L'app non la usa: da qui ognuno
            // vede e gestisce le proprie, chiunque sia. Resta nel payload
            // per il sito e per gli altri client.
            'canManageReports' => $this->canManage($user),
            'ignorePermission' => $user->isIsIgnorePermission(),
        ];
    }

    #[Route('/logout', name: 'api_logout', methods: ['POST'])]
    public function apiLogout(Request $request): JsonResponse
    {
        $user = $this->getAuthenticatedUser($request);
        if (!$user) {
            return $this->errorResponse('Non autenticato.', 401);
        }

        $em = $this->mr->getManager();
        $user->setApiToken(null);
        $em->flush();

        return new JsonResponse(['success' => true, 'message' => 'Logout effettuato.']);
    }

    #[Route('/modifica-password', name: 'api_change_password', methods: ['POST'])]
    public function changePassword(Request $request, UserPasswordHasherInterface $passwordHasher): JsonResponse
    {
        $user = $this->getAuthenticatedUser($request);
        if (!$user) {
            return $this->errorResponse('Non autenticato.', 401);
        }

        $data = json_decode($request->getContent(), true);
        $currentPassword = $data['current_password'] ?? '';
        $newPassword = $data['new_password'] ?? '';

        if (!$currentPassword || !$newPassword) {
            return $this->errorResponse('Password attuale e nuova password sono obbligatorie.');
        }

        if (strlen($newPassword) < 6) {
            return $this->errorResponse('La nuova password deve avere almeno 6 caratteri.');
        }

        if (!$passwordHasher->isPasswordValid($user, $currentPassword)) {
            return $this->errorResponse('La password attuale non è corretta.');
        }

        $em = $this->mr->getManager();
        $hashedPassword = $passwordHasher->hashPassword($user, $newPassword);
        $user->setPassword($hashedPassword);
        $em->flush();

        return new JsonResponse(['success' => true, 'message' => 'Password modificata con successo.']);
    }

    /**
     * Recupero password dall'app, per chi la password non se la ricorda e
     * quindi non puo' passare da '/modifica-password'.
     *
     * Manda la stessa email del sito ('/recupera-password'), con il link a
     * '/crea-password-utente/{oneTimeCode}' valido tre ore: la nuova
     * password si crea da browser e vale sia per l'app sia per l'area
     * riservata.
     *
     * La risposta e' identica sia che l'indirizzo esista sia che non
     * esista: distinguere i due casi darebbe a chiunque il modo di
     * scoprire quali email hanno un account.
     */
    #[Route('/password-dimenticata', name: 'api_forgot_password', methods: ['POST'])]
    public function forgotPassword(Request $request, MailerInterface $mailer): JsonResponse
    {
        $data = json_decode($request->getContent(), true);
        $email = trim((string) ($data['email'] ?? ''));

        if ($email === '') {
            return $this->errorResponse("L'indirizzo email e' obbligatorio.");
        }

        $confirmation = [
            'success' => true,
            'message' => "Se l'indirizzo e' registrato riceverai una email con il link per creare una nuova password. Controlla la casella di posta."
        ];

        $em = $this->mr->getManager();
        $user = $em->getRepository(User::class)->findOneBy(['email' => $email]);

        // Niente email a chi non potrebbe comunque entrare nell'app.
        // isIsActive() qui non si controlla, a differenza di canLogin():
        // e' false anche per l'account staff che la password non l'ha mai
        // creata, ed e' proprio chi questo link deve poter ricevere.
        if (!$user
            || $user->getRole() !== 'ROLE_STAFF'
            || !$user->isIsAdminActive()
            || !$user->getCanViewPermission('reports')) {
            return new JsonResponse($confirmation);
        }

        $user->setOneTimeCode(md5(uniqid()));
        $user->setExpirationOneTimeCode(date_modify(new \DateTime(), '+3 hours'));
        $em->flush();

        $message = (new TemplatedEmail())
            ->from($this->getParameter('email_noreply'))
            ->to($user->getEmail())
            ->subject($this->getParameter('object_recover_password'))
            ->htmlTemplate('email/password_recovery.html.twig')
            ->context(['user' => $user]);

        try {
            $mailer->send($message);
        } catch (TransportExceptionInterface $e) {
            // Il codice e' stato salvato ma l'email non e' partita: senza
            // messaggio l'utente resterebbe ad aspettare una posta che non
            // arrivera' mai, quindi qui si dice che e' andata storta.
            return $this->errorResponse("Non e' stato possibile inviare l'email di recupero. Riprova piu' tardi.", 500);
        }

        return new JsonResponse($confirmation);
    }

    // ==================== REPORT TYPES ====================

    #[Route('/tipi-segnalazione', name: 'api_report_types', methods: ['GET'])]
    public function getReportTypes(Request $request): JsonResponse
    {
        $user = $this->getAuthenticatedUser($request);
        if (!$user) {
            return $this->errorResponse('Non autenticato.', 401);
        }

        $em = $this->mr->getManager();
        $types = $em->getRepository(ReportType::class)->findAllActive();

        $result = [];
        foreach ($types as $type) {
            $result[] = [
                'id' => $type->getId(),
                'name' => $type->getName(),
                'slug' => $type->getSlug(),
                'icon' => $type->getIcon(),
                'icon_file' => $type->getIconFile() ? $this->publicUrl($request, $type->getIconFile()) : null,
                // Graduatoria del tipo: le segnalazioni la ereditano.
                'priority' => $type->getPriority(),
                'priority_label' => $this->priorityLabel($type->getPriority())
            ];
        }

        return new JsonResponse(['success' => true, 'data' => $result]);
    }

    // ==================== REPORTS CRUD ====================

    #[Route('/segnalazioni', name: 'api_reports_list', methods: ['GET'])]
    public function getMyReports(Request $request): JsonResponse
    {
        $user = $this->getAuthenticatedUser($request);
        if (!$user) {
            return $this->errorResponse('Non autenticato.', 401);
        }

        $em = $this->mr->getManager();
        // Filtro esplicito sull'autore, con findBy: l'elenco dell'app e'
        // sempre e solo il proprio, e non deve dipendere da come il
        // repository interpreta un findByUser (che serve anche all'area
        // riservata del sito, dove le segnalazioni si vedono tutte).
        $reports = $em->getRepository(Report::class)->findBy(
            ['user' => $user],
            ['datetime' => 'DESC', 'id' => 'DESC']
        );

        $result = [];
        foreach ($reports as $report) {
            $result[] = $this->serializeReport($request, $report, $user);
        }

        // Il blocco utente viaggia con l'elenco, che l'app richiama a ogni
        // apertura e a ogni pull-to-refresh: cosi' un permesso cambiato sul
        // sito arriva da solo, senza costringere a uscire e rientrare.
        return new JsonResponse([
            'success' => true,
            'data' => $result,
            'user' => $this->serializeUser($user),
        ]);
    }

    #[Route('/segnalazioni/{id}', name: 'api_report_detail', methods: ['GET'])]
    public function getReport(Request $request, string $id): JsonResponse
    {
        $user = $this->getAuthenticatedUser($request);
        if (!$user) {
            return $this->errorResponse('Non autenticato.', 401);
        }

        $em = $this->mr->getManager();
        $report = $em->getRepository(Report::class)->find($id);

        // Dall'app si apre solo la propria: l'elenco non ne contiene altre.
        $isOwner = $report !== null && $report->getUser()?->getId() === $user->getId();
        if (!$report || !$isOwner) {
            return $this->errorResponse('Segnalazione non trovata.', 404);
        }

        return new JsonResponse(['success' => true, 'data' => $this->serializeReport($request, $report, $user)]);
    }

    #[Route('/segnalazioni', name: 'api_report_create', methods: ['POST'])]
    public function createReport(Request $request, ReportNotifier $notifier): JsonResponse
    {
        $user = $this->getAuthenticatedUser($request);
        if (!$user) {
            return $this->errorResponse('Non autenticato.', 401);
        }

        if (!$this->canWrite($user)) {
            return $this->errorResponse("L'account ha le segnalazioni in sola lettura.", 403);
        }

        $em = $this->mr->getManager();

        $typeId = $request->request->get('type_id');
        $details = $request->request->get('details');
        $latitude = $request->request->get('latitude');
        $longitude = $request->request->get('longitude');
        $address = $request->request->get('address');

        if (!$typeId) {
            return $this->errorResponse('Il tipo di segnalazione è obbligatorio.');
        }

        $reportType = $em->getRepository(ReportType::class)->find($typeId);
        if (!$reportType) {
            return $this->errorResponse('Tipo di segnalazione non valido.');
        }

        if ($this->isOutsideCorbetta($latitude, $longitude)) {
            return $this->errorResponse('La posizione indicata non rientra nel territorio del Comune di Corbetta.');
        }

        $status = $request->request->get('status', 'pending');
        if (!in_array($status, self::USER_STATUSES, true)) {
            $status = 'pending';
        }

        $report = new Report();
        $report->setUser($user);
        $report->setReportType($reportType);
        $report->setDatetime(new \DateTime());
        $report->setDetails($details);
        $report->setLatitude($latitude);
        $report->setLongitude($longitude);
        $report->setAddress($address);
        $report->setStatus($status);
        // Non si chiede all'utente: la priorita' e' quella del tipo scelto,
        // numerata dall'area riservata. Resta modificabile a mano dall'admin.
        $report->setPriority($reportType->getPriority() ?? 0);

        $em->persist($report);
        $em->flush();

        // Handle file uploads
        $this->handleAttachments($request, $report);

        // Una bozza non e' ancora una segnalazione: si avvisa chi la deve
        // lavorare solo quando viene inviata davvero.
        if (!$report->isDraft()) {
            $notifier->notifyNewReport($report);
        }

        return new JsonResponse([
            'success' => true,
            'message' => $report->isDraft()
                ? 'Bozza salvata.'
                : 'Segnalazione inviata con successo.',
            'data' => $this->serializeReport($request, $report, $user)
        ], 201);
    }

    #[Route('/segnalazioni/{id}', name: 'api_report_update', methods: ['POST'])]
    public function updateReport(Request $request, string $id, ReportNotifier $notifier): JsonResponse
    {
        $user = $this->getAuthenticatedUser($request);
        if (!$user) {
            return $this->errorResponse('Non autenticato.', 401);
        }

        if (!$this->canWrite($user)) {
            return $this->errorResponse("L'account ha le segnalazioni in sola lettura.", 403);
        }

        $em = $this->mr->getManager();
        $report = $em->getRepository(Report::class)->find($id);

        if (!$report || $report->getUser()->getId() !== $user->getId()) {
            return $this->errorResponse('Segnalazione non trovata.', 404);
        }

        if (!in_array($report->getStatus(), self::EDITABLE_STATUSES, true)) {
            return $this->errorResponse('Solo le bozze e le segnalazioni in attesa possono essere modificate.');
        }

        $typeId = $request->request->get('type_id');
        $details = $request->request->get('details');
        $latitude = $request->request->get('latitude');
        $longitude = $request->request->get('longitude');
        $address = $request->request->get('address');
        $status = $request->request->get('status');

        if ($this->isOutsideCorbetta($latitude, $longitude)) {
            return $this->errorResponse('La posizione indicata non rientra nel territorio del Comune di Corbetta.');
        }

        if ($typeId) {
            $reportType = $em->getRepository(ReportType::class)->find($typeId);
            if ($reportType) {
                $oldType = $report->getReportType();
                // La priorita' segue il tipo solo se non e' stata toccata a
                // mano dall'area riservata: un valore deciso dall'operatore
                // non va perso perche' l'utente cambia tipo alla bozza.
                $inherited = $oldType !== null
                    && $report->getPriority() === $oldType->getPriority();

                $report->setReportType($reportType);

                if ($inherited) {
                    $report->setPriority($reportType->getPriority() ?? 0);
                }
            }
        }

        if ($details !== null) {
            $report->setDetails($details);
        }
        if ($latitude !== null) {
            $report->setLatitude($latitude);
        }
        if ($longitude !== null) {
            $report->setLongitude($longitude);
        }
        if ($address !== null) {
            $report->setAddress($address);
        }

        // Passaggio bozza -> inviata (o salvataggio come bozza).
        // La data resta quella di inserimento: e' il criterio di ordinamento
        // delle liste, non deve cambiare quando la bozza viene inviata.
        $wasDraft = $report->isDraft();
        if ($status !== null && in_array($status, self::USER_STATUSES, true)) {
            $report->setStatus($status);
        }

        // Handle new file uploads
        $this->handleAttachments($request, $report);

        $em->flush();

        // Bozza appena inviata: da adesso e' una segnalazione da lavorare e
        // chi la gestisce va avvisato. Il salvataggio di una segnalazione gia'
        // inviata non manda niente: sarebbe un'email ad ogni correzione.
        if ($wasDraft && !$report->isDraft()) {
            $notifier->notifyNewReport($report);
        }

        return new JsonResponse([
            'success' => true,
            'message' => $report->isDraft() ? 'Bozza salvata.' : 'Segnalazione aggiornata.',
            'data' => $this->serializeReport($request, $report, $user)
        ]);
    }

    /**
     * Elimina una foto (o un allegato) gia' caricato.
     *
     * Serve alla modifica: dall'app si aggiungevano foto e non si potevano
     * piu' togliere, quindi uno scatto sbagliato restava attaccato alla
     * segnalazione per sempre. Vale finche' la segnalazione e' modificabile,
     * cioe' finche' non e' stata presa in carico.
     */
    #[Route('/segnalazioni/{id}/allegati/elimina', name: 'api_report_attachment_delete', methods: ['POST'])]
    public function deleteReportAttachment(Request $request, string $id): JsonResponse
    {
        $user = $this->getAuthenticatedUser($request);
        if (!$user) {
            return $this->errorResponse('Non autenticato.', 401);
        }

        $em = $this->mr->getManager();
        $report = $em->getRepository(Report::class)->find($id);

        if (!$report || $report->getUser()?->getId() !== $user->getId()) {
            return $this->errorResponse('Segnalazione non trovata.', 404);
        }

        if (!$this->canWrite($user)) {
            return $this->errorResponse("L'account ha le segnalazioni in sola lettura.", 403);
        }

        if (!in_array($report->getStatus(), self::EDITABLE_STATUSES, true)) {
            return $this->errorResponse('La segnalazione e\' stata presa in carico: le foto non si possono piu\' togliere.');
        }

        // Il nome arriva dal client: basename() impedisce di uscire dalla
        // cartella della segnalazione con un "../".
        $data = json_decode($request->getContent(), true);
        $fileName = basename((string) ($data['file_name'] ?? $request->request->get('file_name', '')));

        $uploadDir = $this->webPath->dir('/uploads/reports/'.$report->getId().'/');
        if ($fileName === '' || $fileName === '.' || !is_file($uploadDir.$fileName)) {
            return $this->errorResponse('Allegato non trovato.', 404);
        }

        @unlink($uploadDir.$fileName);
        @unlink($uploadDir.self::THUMB_PREFIX.$fileName);

        return new JsonResponse([
            'success' => true,
            'message' => 'Foto eliminata.',
            'data' => $this->serializeReport($request, $report, $user)
        ]);
    }

    #[Route('/segnalazioni/{id}/elimina', name: 'api_report_delete', methods: ['POST'])]
    public function deleteReport(Request $request, string $id): JsonResponse
    {
        $user = $this->getAuthenticatedUser($request);
        if (!$user) {
            return $this->errorResponse('Non autenticato.', 401);
        }

        if (!$this->canWrite($user)) {
            return $this->errorResponse("L'account ha le segnalazioni in sola lettura.", 403);
        }

        $em = $this->mr->getManager();
        $report = $em->getRepository(Report::class)->find($id);

        if (!$report || $report->getUser()->getId() !== $user->getId()) {
            return $this->errorResponse('Segnalazione non trovata.', 404);
        }

        if (!in_array($report->getStatus(), self::EDITABLE_STATUSES, true)) {
            return $this->errorResponse('Solo le bozze e le segnalazioni in attesa possono essere eliminate.');
        }

        $uploadDir = $this->webPath->dir('/uploads/reports/'.$report->getId().'/');
        if (is_dir($uploadDir)) {
            foreach (scandir($uploadDir) as $filename) {
                if ($filename !== '.' && $filename !== '..') {
                    @unlink($uploadDir.$filename);
                }
            }
            @rmdir($uploadDir);
        }

        $em->remove($report);
        $em->flush();

        return new JsonResponse(['success' => true, 'message' => 'Segnalazione eliminata.']);
    }

    // ==================== GEOCODING ====================

    #[Route('/autocomplete-indirizzo', name: 'api_autocomplete_address', methods: ['GET'])]
    public function autocompleteAddress(Request $request): JsonResponse
    {
        $user = $this->getAuthenticatedUser($request);
        if (!$user) {
            return $this->errorResponse('Non autenticato.', 401);
        }

        $q = trim($request->query->get('q', ''));
        if (strlen($q) < 3) {
            return new JsonResponse(['success' => true, 'data' => []]);
        }

        // La ricerca e' vincolata al bounding box di Corbetta: viewbox +
        // bounded=1 fa scartare a Nominatim tutto cio' che sta fuori.
        $url = 'https://nominatim.openstreetmap.org/search?'
            .http_build_query([
                'q' => $q,
                'format' => 'json',
                'addressdetails' => 1,
                'limit' => 8,
                'countrycodes' => 'it',
                'viewbox' => self::CORBETTA_BOUNDS['minLon'].','.self::CORBETTA_BOUNDS['maxLat']
                    .','.self::CORBETTA_BOUNDS['maxLon'].','.self::CORBETTA_BOUNDS['minLat'],
                'bounded' => 1,
            ]);

        $ctx = stream_context_create(['http' => ['header' => "User-Agent: castellazzodestampi-app/1.0\r\n", 'timeout' => 8]]);
        $raw = @file_get_contents($url, false, $ctx);
        if (!$raw) {
            return new JsonResponse(['success' => true, 'data' => []]);
        }

        $results = json_decode($raw, true) ?? [];
        $data = [];
        foreach ($results as $r) {
            // doppio controllo: il viewbox e' un rettangolo, il confine no
            if (!isset($r['lat'], $r['lon'])
                || !$this->isInsideCorbetta((float) $r['lat'], (float) $r['lon'])) {
                continue;
            }
            $data[] = [
                'display_name' => $r['display_name'] ?? '',
                'lat' => $r['lat'] ?? '',
                'lon' => $r['lon'] ?? '',
            ];
            if (count($data) >= 5) {
                break;
            }
        }

        return new JsonResponse(['success' => true, 'data' => $data]);
    }

    #[Route('/reverse-geocode', name: 'api_reverse_geocode', methods: ['GET'])]
    public function reverseGeocode(Request $request): JsonResponse
    {
        $user = $this->getAuthenticatedUser($request);
        if (!$user) {
            return $this->errorResponse('Non autenticato.', 401);
        }

        $lat = $request->query->get('lat', '');
        $lon = $request->query->get('lon', '');

        if (!$lat || !$lon) {
            return $this->errorResponse('Parametri lat e lon obbligatori.');
        }

        $url = 'https://nominatim.openstreetmap.org/reverse?'
            .http_build_query([
                'lat' => $lat,
                'lon' => $lon,
                'format' => 'json',
                'addressdetails' => 1,
            ]);

        $ctx = stream_context_create(['http' => ['header' => "User-Agent: castellazzodestampi-app/1.0\r\n", 'timeout' => 8]]);
        $raw = @file_get_contents($url, false, $ctx);
        if (!$raw) {
            return new JsonResponse(['success' => true, 'data' => null]);
        }

        $result = json_decode($raw, true) ?? [];
        $addr = $result['address'] ?? [];
        $parts = array_filter([
            $addr['road'] ?? null,
            isset($addr['house_number']) ? $addr['house_number'] : null,
            $addr['village'] ?? $addr['town'] ?? $addr['city'] ?? null,
        ]);

        $address = implode(', ', $parts) ?: ($result['display_name'] ?? null);

        // L'app usa in_corbetta per bloccare l'invio da fuori territorio.
        $inCorbetta = $this->isInsideCorbetta((float) $lat, (float) $lon);

        return new JsonResponse(['success' => true, 'data' => [
            'address' => $address,
            'in_corbetta' => $inCorbetta,
        ]]);
    }

    // ==================== HELPERS ====================

    private function handleAttachments(Request $request, Report $report): void
    {
        $files = $request->files->get('attachments');
        if (!$files) {
            return;
        }

        if (!is_array($files)) {
            $files = [$files];
        }

        $uploadDir = $this->webPath->dir('/uploads/reports/'.$report->getId().'/');
        if (!is_dir($uploadDir)) {
            mkdir($uploadDir, 0755, true);
        }
        @chmod($uploadDir, 0755);

        foreach ($files as $file) {
            if (!$file || !$file->isValid()) {
                continue;
            }

            $extension = strtolower($file->guessExtension() ?? $file->getClientOriginalExtension());
            $fileName = uniqid().'.'.$extension;

            $file->move($uploadDir, $fileName);
            @chmod($uploadDir . $fileName, 0644);

            $this->compressIfLarge($uploadDir, $fileName, $extension);
            $this->createThumbnail($uploadDir, $fileName, $extension);
        }
    }

    /**
     * Ricomprime in place le immagini che superano 1 MB (max lato 1600px).
     * L'app comprime gia' prima dell'invio: questo copre gli altri client.
     */
    private function compressIfLarge(string $uploadDir, string $fileName, string $extension): void
    {
        if (!in_array($extension, self::THUMB_EXTENSIONS, true)) {
            return;
        }

        $path = $uploadDir.$fileName;
        if (!is_file($path) || filesize($path) <= self::COMPRESS_THRESHOLD_BYTES) {
            return;
        }

        try {
            MediaService::createPhoto(
                $extension,
                $uploadDir,
                $fileName,
                self::COMPRESS_MAX_SIZE,
                self::COMPRESS_QUALITY,
                false,
                false
            );
        } catch (\Throwable $e) {
            // compressione fallita: si tiene il file originale
        }
    }

    /**
     * Genera la miniatura da 300px usata nelle gallery (app e area admin).
     * Se GD non riesce a leggere il file la gallery ricade sull'originale.
     */
    private function createThumbnail(string $uploadDir, string $fileName, string $extension): void
    {
        if (!in_array($extension, self::THUMB_EXTENSIONS, true)) {
            return;
        }

        try {
            MediaService::createPhoto(
                $extension,
                $uploadDir,
                $fileName,
                self::THUMB_SIZE,
                self::THUMB_QUALITY,
                true,
                false
            );
        } catch (\Throwable $e) {
            // nessuna thumbnail: si usa l'immagine originale
        }
    }

    /**
     * true se le coordinate sono valorizzate e cadono fuori dal territorio
     * di Corbetta. Senza coordinate non e' possibile decidere: non blocca.
     */
    private function isOutsideCorbetta(?string $latitude, ?string $longitude): bool
    {
        if ($latitude === null || $longitude === null || $latitude === '' || $longitude === '') {
            return false;
        }

        return !$this->isInsideCorbetta((float) $latitude, (float) $longitude);
    }

    /**
     * true se il punto sta dentro il confine reale di Corbetta (stesso
     * controllo dell'app, lib/utils/corbetta_boundary.dart).
     */
    private function isInsideCorbetta(float $lat, float $lon): bool
    {
        if ($lat < self::CORBETTA_BOUNDS['minLat'] || $lat > self::CORBETTA_BOUNDS['maxLat']
            || $lon < self::CORBETTA_BOUNDS['minLon'] || $lon > self::CORBETTA_BOUNDS['maxLon']) {
            return false;
        }

        $polygon = $this->corbettaPolygon();

        // Ray-Casting: linea dal punto verso est, si contano i lati del
        // confine attraversati. Dispari = dentro, pari = fuori.
        $inside = false;
        $count = count($polygon);
        for ($i = 0, $j = $count - 1; $i < $count; $j = $i++) {
            [$latI, $lonI] = $polygon[$i];
            [$latJ, $lonJ] = $polygon[$j];
            if (($latI > $lat) !== ($latJ > $lat)
                && $lon < ($lonJ - $lonI) * ($lat - $latI) / ($latJ - $latI) + $lonI) {
                $inside = !$inside;
            }
        }

        return $inside;
    }

    /** Poligono del confine, letto dal file una volta per richiesta. */
    private function corbettaPolygon(): array
    {
        if ($this->corbettaPolygon === null) {
            $file = $this->getParameter('kernel.project_dir').self::CORBETTA_BOUNDARY_FILE;
            $raw = @file_get_contents($file);
            $polygon = $raw ? json_decode($raw, true) : null;
            if (!is_array($polygon) || count($polygon) < 3) {
                throw new \RuntimeException('Confine di Corbetta mancante o non valido: '.$file);
            }
            $this->corbettaPolygon = $polygon;
        }

        return $this->corbettaPolygon;
    }

    // ==================== PRIORITA' ====================

    // La priorita' di una segnalazione non viene chiesta all'utente: la
    // eredita dal tipo scelto, che porta la graduatoria numerata dall'area
    // riservata. Convenzione: valore piu' ALTO = piu' urgente (4-5 Alta,
    // 0-3 Bassa). Le soglie stanno in ReportPriorityService, unico punto in
    // cui vanno cambiate: app e area riservata leggono da la'.

    private function priorityLabel(?int $priority): string
    {
        return $this->priority->label($priority);
    }

    private function serializeReport(Request $request, Report $report, ?User $user = null): array
    {
        $attachments = [];
        $uploadDir = $this->webPath->dir('/uploads/reports/'.$report->getId().'/');
        if (is_dir($uploadDir)) {
            $imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
            $baseUrl = $this->publicUrl($request, 'uploads/reports/'.$report->getId().'/');
            foreach (scandir($uploadDir) as $filename) {
                if ($filename === '.' || $filename === '..') {
                    continue;
                }
                // le miniature non sono allegati a se' stanti
                if (str_starts_with($filename, self::THUMB_PREFIX)) {
                    continue;
                }
                $ext = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
                $isImage = in_array($ext, $imageExtensions);
                $thumbName = self::THUMB_PREFIX.$filename;
                $hasThumb = $isImage && is_file($uploadDir.$thumbName);
                $attachments[] = [
                    'file_name' => $filename,
                    'file_path' => $baseUrl.$filename,
                    // ricade sull'originale per le immagini caricate prima delle thumbnail
                    'thumb_path' => $baseUrl.($hasThumb ? $thumbName : $filename),
                    'file_type' => $isImage ? 'image/'.$ext : 'file/'.$ext,
                    'uploaded_at' => date('Y-m-d H:i:s', filemtime($uploadDir.$filename))
                ];
            }
        }

        return [
            'id' => $report->getId(),
            'type' => [
                'id' => $report->getReportType()->getId(),
                'name' => $report->getReportType()->getName(),
                'slug' => $report->getReportType()->getSlug(),
                'icon_file' => $report->getReportType()->getIconFile()
                    ? $this->publicUrl($request, $report->getReportType()->getIconFile())
                    : null
            ],
            'datetime' => $report->getDatetime()->format('Y-m-d H:i:s'),
            'latitude' => $report->getLatitude(),
            'longitude' => $report->getLongitude(),
            'address' => $report->getAddress(),
            'priority' => $report->getPriority(),
            'priority_label' => $this->priorityLabel($report->getPriority()),
            'details' => $report->getDetails(),
            'status' => $report->getStatus(),
            'status_label' => $report->getStatusLabel(),
            // Chi vede tutte le segnalazioni ne ha in elenco anche di altri:
            // questi due campi dicono all'app quali schede aprono i pulsanti
            // Modifica ed Elimina, senza che debba dedurlo dal permesso globale.
            'is_owner' => $user !== null && $report->getUser()?->getId() === $user->getId(),
            'can_edit' => $user !== null && $this->canEditReport($user, $report),
            'attachments' => $attachments
        ];
    }
}
