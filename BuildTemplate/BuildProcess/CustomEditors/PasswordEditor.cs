using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Drawing.Design;
using System.ComponentModel;
using System.Windows.Forms.Design;
using System.Windows.Forms;
using System.Diagnostics;

namespace BuildProcess.CustomEditors
{
    class PasswordEditor : UITypeEditor
    {
        public override object EditValue(ITypeDescriptorContext context, IServiceProvider provider, object value)
        {
            if (provider != null)
            {
                IWindowsFormsEditorService editorService = (IWindowsFormsEditorService)provider.GetService(typeof(IWindowsFormsEditorService));

                if (editorService != null)
                {
                    Password password = value as Password;

                    using (PasswordDialog dialog = new PasswordDialog())
                    {
                        //dialog.Password = password.PasswordField;

                        if (editorService.ShowDialog(dialog) == DialogResult.OK)
                        {
                           // if (!String.IsNullOrEmpty(dialog.Password))
                          //  {
                          //      Process proc = executeCommand(dialog.Password);
                            //    proc.Start();

                                // Get the output of the command
                                password.PasswordField = dialog.Password;
                            //}
//else
                           // {
                             //   password.PasswordField = dialog.Password;
                           // }
                        }
                    }
                }

            }

            return value;

        }

        public override UITypeEditorEditStyle GetEditStyle(ITypeDescriptorContext context)
        {
            return UITypeEditorEditStyle.Modal;
        }

    }
}
