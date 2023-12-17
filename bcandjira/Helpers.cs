using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace bcandjira
{
    public class Helpers
    {
        public static bool CheckHandkShake(string? handshakewordfromrequest)
        {
            string checkhandshakeword = Environment.GetEnvironmentVariable("handshakeword");

            if (handshakewordfromrequest != checkhandshakeword)
            {
                return false;
            }

            return true;
        }
    }
}
