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
            string maskedPassword = "";

            for (int i = 0; i < PasswordField.Length; i++)
            {
                maskedPassword += "*";
            }

            return maskedPassword;
        }
    }
}
