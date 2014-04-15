using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.TeamFoundation.Build.Client;

namespace BuildProcess.CustomEditors
{
    [BuildExtension(HostEnvironmentOption.All)]
    public class Password
    {
        public string PasswordField { get; set; }
        
        public override string ToString()
        {
            byte[] bytesToEncode = Encoding.UTF8.GetBytes(PasswordField);
            string encodedText = Convert.ToBase64String(bytesToEncode);

            return encodedText;
        }
    }
}
