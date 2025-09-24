// C:\projet appli\flutter_application_1\functions\index.js

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Callable function to add an admin role (custom claim) to a user.
 * @param {object} data - The data passed to the function.
 * @param {string} data.email - The email of the user to make an admin.
 * @param {functions.https.CallableContext} context - The context of the call.
 * @returns {Promise<{message: string}>} A promise that resolves with a
 *   success message.
 * @throws {functions.https.HttpsError} If the caller is not authorized,
 *   email is missing, or an error occurs.
 */
exports.addAdminRole = functions.https.onCall(async (data, context) => {
  // Sécurité : Vérifier si l'appelant est déjà un admin.
  // Pour le tout premier admin, vous devrez peut-être commenter cette
  // vérification ou avoir un moyen de le définir manuellement la
  // première fois (par exemple, via un script local).
  // IMPORTANT : Adaptez cette condition de sécurité à votre besoin.
  // Si `context.auth` est null, l'utilisateur n'est pas authentifié.
  // Si `context.auth.token.admin` n'est pas true, l'utilisateur
  // authentifié n'est pas admin.
  if (!context.auth || context.auth.token.admin !== true) {
    // Optionnel : Pour un "super admin" initial
    // if (!context.auth || (
    //   context.auth.token.admin !== true &&
    //   context.auth.token.superAdmin !== true
    // )) {
    const userId = context.auth ? context.auth.uid : "Non authentifié";
    console.log(
        `Appel non autorisé pour addAdminRole par UID: ${userId}`,
    );
    throw new functions.https.HttpsError(
        "permission-denied",
        "Seul un administrateur peut ajouter d'autres administrateurs.",
    );
  }

  const email = data.email;
  if (!email || typeof email !== "string") {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "L'email (chaîne de caractères) est requis.",
    );
  }

  try {
    const user = await admin.auth().getUserByEmail(email);
    // Définir le custom claim 'admin' à true
    await admin.auth().setCustomUserClaims(user.uid, {admin: true});
    console.log(
        `Rôle admin ajouté pour ${email} (UID: ${user.uid}) par ` +
        `${context.auth.uid}`,
    );
    return {
      message: `Succès! ${email} est maintenant un administrateur.`,
    };
  } catch (error) {
    console.error(
        `Erreur lors de l'attribution du rôle admin à ${email}:`,
        error,
    );
    // Transmettre un message d'erreur plus général au client
    if (error.code === "auth/user-not-found") {
      throw new functions.https.HttpsError(
          "not-found",
          `Aucun utilisateur trouvé pour l'email: ${email}`,
      );
    }
    throw new functions.https.HttpsError(
        "internal",
        "Une erreur est survenue lors de l'attribution du rôle admin.",
    );
  }
});

// Vous pouvez ajouter d'autres fonctions ici, par exemple:
// exports.removeAdminRole = functions.https.onCall(async (data, context) => {
//   // ... logique similaire
// });

