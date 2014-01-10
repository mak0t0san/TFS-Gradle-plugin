using System;
using System.Xml;
using System.Collections.Generic;
using System.Diagnostics;
using System.Activities;
using Microsoft.TeamFoundation.Build.Client;
using Microsoft.TeamFoundation.Build.Workflow.Activities;

namespace DeploymentToAzureVM
{
    
    public class DeploymentToAzureVM : CodeActivity
    {
        // VM Config File XML Elements
        private const string VM = "VM";
        private const string IMAGE_TYPE = "ImageType";
        private const string VIP = "VIP";
        private const string USER_NAME = "UserName";
        private const string DEPLOYMENT_PATH = "DeploymentPath";
        private const string SSH_PORT = "StandaloneSSHPublicPort";
        private const string PASSWORD = "Password";
        private const string SSH_KEY_PATH = "SSHPrivateKeyPath";

        // VM Config File XML Values
        private const string LINUX = "Linux";
        
        // Holds all the XML Elements and Values within each <VM>...</VM> tags
        private Dictionary<string, string> vmConfig;
        
        // Holds the current XML Element being read. Used for logging in case of errors.
        private string vmConfigElementLog;

        private CodeActivityContext context;

        [RequiredArgument]
        public InArgument<string> BuildOutputPath { get; set; }

        [RequiredArgument]
        public InArgument<string> AzureVMsConfigFile { get; set; }

        protected override void Execute(CodeActivityContext context)
        {
            this.context = context;

            readVMConfigAndDeploy();
        }

        private void readVMConfigAndDeploy()
        {
            // Create XML reader settings
            XmlReaderSettings settings = new XmlReaderSettings();
            settings.IgnoreComments = true;
            settings.IgnoreWhitespace = true;

            XmlReader reader = XmlReader.Create(context.GetValue(this.AzureVMsConfigFile), settings);

            string key;
            string value;
            string pscpCmd;

            while (reader.Read())
            {
                vmConfig = new Dictionary<string, string>();
                vmConfigElementLog = "";

                if (reader.NodeType == XmlNodeType.Element && String.Compare(reader.Name, VM, true) == 0)
                {
                    // Read all the elements within <VM>...</VM>
                    while (reader.Read())
                    {
                        key = "";
                        value = "";

                        if (reader.NodeType == XmlNodeType.Element)
                        {
                            key = reader.Name;
                            reader.Read();
                            if (reader.NodeType == XmlNodeType.Text)
                            {
                                value = reader.Value;
                            }
                            vmConfig.Add(key, value);
                        }
                        else if (reader.NodeType == XmlNodeType.EndElement && String.Compare(reader.Name, VM, true) == 0)
                        {
                            // Finished reading all elements within <VM>...</VM>. Now process them.
                            try
                            {
                                vmConfigElementLog = IMAGE_TYPE;
                                if (String.Compare(vmConfig[IMAGE_TYPE], LINUX, true) == 0)
                                {
                                    pscpCmd = constructPSCPCommand();
                                    executePSCPCommand(pscpCmd);
                                }
                            }
                            catch (KeyNotFoundException knfe)
                            {
                                context.TrackBuildError("The element '" + vmConfigElementLog
                                    + "' is missing in the VM Config file!! \n" + knfe.StackTrace);
                                throw knfe;
                            }

                            // Break from the inner loop which is reading from <VM>...till </VM>, 
                            // so that you fetch the next set of <VM>...</VM> values
                            break;
                        }
                    }
                }
            }
        }

        private string constructPSCPCommand()
        {
            string pscpCmd = "pscp";

            // Hold the PSCP commands after masking the password and SSH Key Path.
            // This will be used for logging.
            string pscpCmdMasked;

            vmConfigElementLog = "";

            try
            {
                vmConfigElementLog = USER_NAME;
                pscpCmd += " -l " + vmConfig[USER_NAME]; 					// Append user name
                pscpCmdMasked = pscpCmd;

                // Password or SSH Key path needs to be present
                if (vmConfig.ContainsKey(PASSWORD))
                {
                    pscpCmd += " -pw " + vmConfig[PASSWORD];				// Append password
                    pscpCmdMasked += " -pw ****";							// To avoid logging the actual password
                }
                else if (vmConfig.ContainsKey(SSH_KEY_PATH))
                {
                    pscpCmd += " -i \"" + vmConfig[SSH_KEY_PATH] + "\""; 	// Append SSH Private Key Path
                    pscpCmdMasked += " -i ****";							// To avoid logging the actual SSH Key Path
                }
                else
                {
                    // Neither password nor SSH Key are provided
                    throw new Exception("Neither Password nor SSH Key Path is provided. Check the VM Config again!!");
                }

                vmConfigElementLog = SSH_PORT;
                pscpCmd += " -P " + vmConfig[SSH_PORT];						// Append SSH Port
                pscpCmdMasked += " -P " + vmConfig[SSH_PORT];

                pscpCmd += " -r \"" + context.GetValue(this.BuildOutputPath) + "\" ";				// Append Build Output Folder
                pscpCmdMasked += " -r \"" + context.GetValue(this.BuildOutputPath) + "\" ";

                vmConfigElementLog = VIP + " OR " + DEPLOYMENT_PATH;
                pscpCmd += vmConfig[VIP] + ":" + vmConfig[DEPLOYMENT_PATH];	// Append VIP and Deployment path
                pscpCmdMasked += vmConfig[VIP] + ":" + vmConfig[DEPLOYMENT_PATH];

                context.TrackBuildMessage(pscpCmdMasked, BuildMessageImportance.High);
                return pscpCmd;
            }
            catch (KeyNotFoundException knfe)
            {
                context.TrackBuildError("The element '" + vmConfigElementLog
                    + "' is missing in the VM Config file!! \n" + knfe.StackTrace);
                throw knfe;
            }
        }

        private void executePSCPCommand(string pscpCmd)
        {
            ProcessStartInfo procStartInfo;
            Process proc;

            // When PSCP command is run, it will be interactive and will ask for a confirmation
            // of the VM's RSA Key Fingerprint. Hence piping "echo y" will auto-answer it.
            procStartInfo = new ProcessStartInfo("cmd", "/C echo y | " + pscpCmd);

            // Redirect the standard input, output and error to the Process.StandardInput, Process.StandardOutput and 
            // Process.StandardError StreamReader.
            procStartInfo.RedirectStandardInput = true;
            procStartInfo.RedirectStandardOutput = true;
            procStartInfo.RedirectStandardError = true;

            procStartInfo.UseShellExecute = false;

            // Do not create the black window.
            procStartInfo.CreateNoWindow = true;

            proc = new Process();
            proc.StartInfo = procStartInfo;
            proc.Start();

            // Get the output and error into a string
            string result = proc.StandardOutput.ReadToEnd();
            string error = proc.StandardError.ReadToEnd();

            // Display the command output / error
            if (String.IsNullOrEmpty(error))
            {
                context.TrackBuildMessage(result, BuildMessageImportance.High); 
            }
            else
            {
                // This is done so that the interactive prompt is not considered as error.
                // The 'echo y' would supply the input.
                if (error.StartsWith("The server's host key is not cached in the registry"))
                {
                    // Log the Standard Output and not the Error
                    context.TrackBuildMessage(result, BuildMessageImportance.High); 
                }
                else
                {
                    context.TrackBuildError(error);
                }
            }            
        }
    }
}
