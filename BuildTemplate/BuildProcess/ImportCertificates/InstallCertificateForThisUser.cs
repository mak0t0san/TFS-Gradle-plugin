using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Activities;
using System.Security.Cryptography.X509Certificates;

namespace BuildProcess.ImportCertificates
{

    public sealed class InstallCertificateForThisUser : CodeActivity<string>
    {
        public InArgument<string> Certificate { get; set; }

        protected override string Execute(CodeActivityContext context)
        {
            string CertificatePath = context.GetValue(this.Certificate);

            string cThumbprint = string.Empty;
            X509Certificate2 certificate = new X509Certificate2(CertificatePath);
            X509Store store = new X509Store(StoreName.My, StoreLocation.CurrentUser);

            store.Open(OpenFlags.ReadWrite);
            store.Add(certificate);
            cThumbprint = certificate.Thumbprint;
            store.Close();

            return cThumbprint;
        }
    }
}
